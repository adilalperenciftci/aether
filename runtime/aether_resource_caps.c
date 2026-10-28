/* aether_resource_caps.c — runtime per-call resource caps (#343).
 *
 * See aether_resource_caps.h for the API contract. This file owns
 * the atomics, the TLS slots, and the clock arithmetic; everything
 * else (cap-aware allocators, codegen tripwire, public libaether
 * forwarders) calls in via the header.
 */

#include "aether_resource_caps.h"
#include "utils/aether_thread.h"
#include "utils/aether_compiler.h"
#include "actors/aether_frames.h"

#include <stdatomic.h>
#include <assert.h>
#include <time.h>

#ifdef _WIN32
#  include <windows.h>
#endif

/* Process-wide. _Atomic for the lock-free fast path — every alloc
 * site touches g_mem_used; contention is real but bounded by the
 * compare-and-add pattern. */
static _Atomic uint64_t g_mem_used = 0;
static _Atomic uint64_t g_mem_cap  = 0;   /* 0 = unlimited */

/* Per-thread. The deadline is monotonic-clock nanoseconds; 0 means
 * "no deadline armed". The tripped flag is sticky once set, until
 * aether_caps_set_deadline_ms is called again. */
static AETHER_TLS_SHARED int64_t g_deadline_at_ns = 0;
static AETHER_TLS_SHARED int     g_tripped        = 0;

/* Monotonic nanoseconds since an arbitrary epoch; only differences
 * matter. Delegates to aether_now_ns so Windows goes through the
 * overflow-free QueryPerformanceCounter split in the thread shim. */
static int64_t now_ns(void) {
    return (int64_t)aether_now_ns();
}

int aether_caps_check_alloc(size_t bytes) {
    /* Fast path: no cap set. One relaxed load + branch. */
    uint64_t cap = atomic_load_explicit(&g_mem_cap, memory_order_relaxed);
    if (cap == 0) {
        /* Still account the alloc so the counter reflects current
         * usage even when no cap is active — keeps test harnesses
         * and future cap-set transitions consistent. */
        atomic_fetch_add_explicit(&g_mem_used, (uint64_t)bytes,
                                  memory_order_relaxed);
        return 1;
    }

    /* Cap-set path: CAS-add to keep current+bytes <= cap. Loop
     * because another thread may bump the counter between our load
     * and our CAS — re-read and retry. */
    uint64_t cur = atomic_load_explicit(&g_mem_used, memory_order_relaxed);
    for (;;) {
        if (cur + (uint64_t)bytes > cap || cur + (uint64_t)bytes < cur) {
            return 0;  /* would exceed cap or wraps */
        }
        if (atomic_compare_exchange_weak_explicit(
                &g_mem_used, &cur, cur + (uint64_t)bytes,
                memory_order_relaxed, memory_order_relaxed)) {
            return 1;
        }
        /* CAS failed; cur is now the latest observed value. Retry. */
    }
}

void aether_caps_account_free(size_t bytes) {
    /* Saturating decrement: never wrap below 0. Underflow would
     * falsely trip the cap on subsequent allocations. */
    uint64_t cur = atomic_load_explicit(&g_mem_used, memory_order_relaxed);
    for (;;) {
        uint64_t next = (cur >= (uint64_t)bytes) ? (cur - (uint64_t)bytes) : 0;
#ifndef NDEBUG
        assert(cur >= (uint64_t)bytes && "alloc/free accounting underflow");
#endif
        if (atomic_compare_exchange_weak_explicit(
                &g_mem_used, &cur, next,
                memory_order_relaxed, memory_order_relaxed)) {
            return;
        }
    }
}

void aether_caps_set_memory_cap(uint64_t bytes) {
    atomic_store_explicit(&g_mem_cap, bytes, memory_order_relaxed);
}

/* Nonzero once any thread has armed or tripped a deadline, or cancelled a
 * call (aether_exec.c). The codegen's loop-head check reads this first, so
 * code that never uses deadlines pays one load instead of a call and two
 * TLS reads. It is never cleared: another thread may still be armed, and
 * the full check below stays exact.
 *
 * Atomic, read with relaxed loads (a plain load on x86 and ARM): a cancel
 * comes from another thread while the call runs, and a loop that started
 * before it must see it. As a plain int, clang read it once before a loop
 * whose body calls nothing and never again, so the loop ran to its end. */
_Atomic int aether_caps_armed = 0;

static inline void caps_arm(void) {
    atomic_store_explicit(&aether_caps_armed, 1, memory_order_relaxed);
}

void aether_caps_set_deadline_ms(int64_t ms) {
    if (ms > 0) caps_arm();
    if (ms <= 0) {
        g_deadline_at_ns = 0;
    } else {
        g_deadline_at_ns = now_ns() + ms * 1000000LL;
    }
    /* Reset the sticky flag — a fresh deadline is a fresh chance. */
    g_tripped = 0;
}

int aether_caps_deadline_tripped(void) {
    if (g_tripped) return 1;
    if (g_deadline_at_ns == 0) return 0;
    if (now_ns() >= g_deadline_at_ns) {
        caps_arm();
        g_tripped = 1;
        return 1;
    }
    return 0;
}

void __aether_abort_call(void) {
    caps_arm();
    g_tripped = 1;
}

void aether_caps_deadline_save(AetherDeadlineState* out) {
    out->at_ns = g_deadline_at_ns;
    out->tripped = g_tripped;
}

void aether_caps_deadline_restore(const AetherDeadlineState* s) {
    if (s->at_ns || s->tripped) caps_arm();
    g_deadline_at_ns = s->at_ns;
    g_tripped = s->tripped;
}

AetherDeadlineState aether_caps_deadline_for_ms(int64_t ms) {
    AetherDeadlineState s;
    s.at_ns = ms > 0 ? now_ns() + ms * 1000000LL : 0;
    s.tripped = 0;
    return s;
}

int aether_caps_deadline_flag(void) {
    return g_tripped;
}

uint64_t aether_caps_used_bytes(void) {
    return atomic_load_explicit(&g_mem_used, memory_order_relaxed);
}

#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------
 * Allocation failure inside an execution (#2956)
 * ------------------------------------------------------------------
 * A cap-aware allocation that fails, past the cap or with the allocator
 * out of memory, returns NULL to its caller, which fails cleanly (an
 * error, its own memory freed), as it does outside an execution. Inside
 * one the failure is also noted on the innermost execution, and its next
 * safe point, or its return, ends it with AETHER_MEMORY_CAP or
 * AETHER_OUT_OF_MEMORY. The call does not unwind from inside the
 * allocator: that would skip the C code between it and the safe point,
 * which holds memory and may hold a lock. */

/* aether_test_fail_alloc_after: one global load per allocation while no
 * test has asked, the count per thread so a test is deterministic. The flag
 * is read by generated code too (_aether_alloc, #3377), so it is exported. */
_Atomic int aether_alloc_test_armed = 0;
static AETHER_TLS_SHARED int t_alloc_fail_after = 0;

void aether_test_fail_alloc_after(int n) {
    t_alloc_fail_after = n > 0 ? n : 0;
    if (n > 0) atomic_store_explicit(&aether_alloc_test_armed, 1, memory_order_relaxed);
}

int aether_alloc_test_refuses(void) {
    if (!atomic_load_explicit(&aether_alloc_test_armed, memory_order_relaxed)) return 0;
    if (t_alloc_fail_after <= 0) return 0;
    return --t_alloc_fail_after == 0;
}

void aether_alloc_failed(int why) {
    AetherFrames* F = aether_frames_here();
    if (F->exec_depth <= F->exec_floor) return;   /* none of this code's (#3392) */
    AetherExecRecord* x = &F->exec[F->exec_depth - 1];
    if (!x->stop) x->stop = why;
    caps_arm();
}

/* Libc-compatible wrappers: the returned pointer has no hidden
 * header, so libc free() is safe (loses cap accounting but no
 * heap corruption). For full cap accounting, callers free with
 * aether_caps_free(p, bytes) passing the original size. */

void* aether_caps_malloc(size_t bytes) {
    if (aether_alloc_test_refuses()) {
        aether_alloc_failed(AETHER_STOP_OUT_OF_MEMORY);
        return NULL;
    }
    if (!aether_caps_check_alloc(bytes)) {
        aether_alloc_failed(AETHER_STOP_MEMORY_CAP);
        return NULL;
    }
    void* p = malloc(bytes);
    if (!p) {
        aether_caps_account_free(bytes);
        aether_alloc_failed(AETHER_STOP_OUT_OF_MEMORY);
        return NULL;
    }
    return p;
}

void* aether_caps_calloc(size_t n, size_t size) {
    if (size != 0 && n > (size_t)-1 / size) {
        aether_alloc_failed(AETHER_STOP_OUT_OF_MEMORY);
        return NULL;
    }
    size_t bytes = n * size;
    if (aether_alloc_test_refuses()) {
        aether_alloc_failed(AETHER_STOP_OUT_OF_MEMORY);
        return NULL;
    }
    if (!aether_caps_check_alloc(bytes)) {
        aether_alloc_failed(AETHER_STOP_MEMORY_CAP);
        return NULL;
    }
    void* p = calloc(n, size);
    if (!p) {
        aether_caps_account_free(bytes);
        aether_alloc_failed(AETHER_STOP_OUT_OF_MEMORY);
        return NULL;
    }
    return p;
}

void* aether_caps_realloc(void* p, size_t old_bytes, size_t new_bytes) {
    if (new_bytes > old_bytes && aether_alloc_test_refuses()) {
        aether_alloc_failed(AETHER_STOP_OUT_OF_MEMORY);
        return NULL;
    }
    if (new_bytes > old_bytes) {
        size_t delta = new_bytes - old_bytes;
        if (!aether_caps_check_alloc(delta)) {
            aether_alloc_failed(AETHER_STOP_MEMORY_CAP);
            return NULL;
        }
    }
    void* np = realloc(p, new_bytes);
    if (!np) {
        if (new_bytes > old_bytes) {
            aether_caps_account_free(new_bytes - old_bytes);
        }
        if (new_bytes) aether_alloc_failed(AETHER_STOP_OUT_OF_MEMORY);
        return NULL;
    }
    if (new_bytes < old_bytes) {
        aether_caps_account_free(old_bytes - new_bytes);
    }
    return np;
}

void aether_caps_free(void* p, size_t bytes) {
    if (!p) return;
    free(p);
    aether_caps_account_free(bytes);
}

/* ------------------------------------------------------------------
 * Stop checks of an execution (#2956, runtime/aether_exec.h): its
 * deadline, or a cancel from another thread. Here, with the deadline they
 * read, so a C-backed std operation can ask without linking the execution
 * frames (the compiler links the std objects and this file).
 * ------------------------------------------------------------------ */


int aether_exec_stop_reason(void) {
    AetherFrames* F = aether_frames_here();
    if (aether_caps_deadline_tripped()) return AETHER_STOP_DEADLINE;
    AetherCancelCell* c = F->cell;
    if (!c) return 0;
    uint64_t s = atomic_load_explicit(&c->pending, memory_order_acquire);
    if (!s) return 0;
    /* The cancelled execution, or one nested inside it: the innermost goes
     * first; the cancelled one at its own next safe point, once the host
     * code between them has returned. One an actor step runs inside is not
     * this code's to stop, and is not spent either: it waits (#3392). */
    for (int i = F->exec_depth - 1; i >= 0; i--)
        if (F->exec[i].serial == s) return i >= F->exec_floor ? AETHER_STOP_CANCELLED : 0;
    /* A cancel for an execution that already ended: spent. One that has not
     * begun yet waits for it. */
    if (s <= F->serial)
        atomic_compare_exchange_strong_explicit(&c->pending, &s, 0, memory_order_acq_rel,
                                                memory_order_relaxed);
    return 0;
}

int aether_exec_should_stop(void) {
    if (!atomic_load_explicit(&aether_caps_armed, memory_order_relaxed)) return 0;
    AetherFrames* F = aether_frames_here();
    if (F->exec_depth <= F->exec_floor) return 0;
    /* Already stopping (an allocation failed, or an earlier check): stop. */
    if (F->exec[F->exec_depth - 1].stop) return 1;
    int why = aether_exec_stop_reason();
    if (why) F->exec[F->exec_depth - 1].stop = why;
    return why != 0;
}
