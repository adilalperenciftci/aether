// Allocation journal: deterministic heap cleanup on panic unwind.
// See aether_unwind.h for the invariant and the link-surface warning
// that keeps this out of aether_panic.c.

#include "aether_unwind.h"
#include "../utils/aether_compiler.h"
#include "aether_frames.h"
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* An entry is a value (`free_fn(ptr)` on a drain) or a place (#2923): `ptr`
 * is the address of a slot holding a value, `owned` the address of the flag
 * that says the slot owns it (NULL: it owns whatever it holds), and a drain
 * releases what the slot holds then, leaving it empty. */
typedef struct AetherUnwindEntry {
    const void* ptr;
    const void* owned;
    AetherUnwindFree free_fn;
    int depth;
    unsigned char place;     /* a place, not a value */
    unsigned char draining;  /* to be released by the drain running now */
} AetherUnwindEntry;


/* The per-thread frames block (aether_frames.h): the try and execution
 * frames, the executions' records, the journal. Owned by this file and read
 * only here: every other file, the runtime's included, reaches it through
 * aether_frames_here() and never names the thread-local (aether_frames.h
 * says why). The paths every actor step and every `try` take, the frames'
 * push and pop and the journal, are here so they read it directly.
 * AETHER_TLS_SHARED, not AETHER_TLS: this object is pulled into both
 * executables and --emit=lib shared objects (the emitted prologue
 * references the track/forget symbols from every program). Initial-Exec
 * TLS relocations do not work inside shared objects; Global-Dynamic works
 * in both contexts. Here rather than in aether_panic.c, so that journaling
 * pulls in no more than this file. */
static AETHER_TLS_SHARED AetherFrames t_frames;

AetherFrames* aether_frames_here(void) {
    return &t_frames;
}

AetherJmpFrame* aether_try_push(void) {
    AetherFrames* F = &t_frames;
    if (F->depth >= AETHER_PANIC_MAX_DEPTH) {
        fprintf(stderr, "aether: try/catch nesting exceeded %d, aborting\n",
                AETHER_PANIC_MAX_DEPTH);
        abort();
    }
    AetherJmpFrame* f = &F->frames[F->depth++];
    f->reason = NULL;
    f->reason_release = NULL;
    f->exec_buf = NULL;
    return f;
}

/* aether_frames.h. NULL until a library call ran on some thread of this
 * runtime copy: until then no step can find an execution to put aside. */
void (*_Atomic aether_step_execs_hook)(AetherExecAside* s, int hide) = NULL;

/* The executions an actor step runs inside are not its own (#3392): it is
 * code a library call reached, a send's inline step or a cooperative ask's
 * poll, not the call. Above the floor, the step's own: a loop head in its
 * handler sees no call's deadline or cancel, a try catches its ordinary
 * panics (no interruption is on its way), a failed allocation notes no stop
 * for the call, and its caller info is none. */
static void step_put_aside_execs(AetherFrames* F, AetherExecAside* s) {
    s->exec_floor = F->exec_floor;
    s->interrupting = F->interrupting;
    F->exec_floor = F->exec_depth;
    F->interrupting = 0;
    void (*hook)(AetherExecAside*, int) = atomic_load_explicit(&aether_step_execs_hook,
                                                               memory_order_acquire);
    s->execs_part = hook != NULL;
    if (hook) hook(s, 1);
}

AetherJmpFrame* aether_step_push(AetherExecAside* s, int* hid) {
    AetherFrames* F = &t_frames;
    /* An execution above the floor, or an interruption on its way (its
     * unwind runs defers, which can send): the step puts them aside. */
    *hid = 0;
    if (unlikely(F->exec_depth != F->exec_floor || F->interrupting)) {
        step_put_aside_execs(F, s);
        *hid = 1;
    }
    return aether_try_push();
}

void aether_step_give_back_execs(const AetherExecAside* s) {
    AetherFrames* F = &t_frames;
    if (s->execs_part) {
        void (*hook)(AetherExecAside*, int) = atomic_load_explicit(&aether_step_execs_hook,
                                                                   memory_order_acquire);
        hook((AetherExecAside*)s, 0);
    }
    F->exec_floor = s->exec_floor;
    F->interrupting = s->interrupting;
}

void aether_try_pop(void) {
    AetherFrames* F = &t_frames;
    if (F->depth <= 0) {
        // Defensive: popping an empty stack means codegen/runtime mismatch.
        fprintf(stderr, "aether: aether_try_pop on empty stack\n");
        abort();
    }
    /* The journal's entries of this frame move to its parent (or go, at
     * depth zero): only when it has any. */
    if (F->journal_count) aether_unwind_exit_frame();
    F->depth--;
}

AetherJmpFrame* aether_current_frame(void) {
    AetherFrames* F = &t_frames;
    if (F->depth == 0) return NULL;
    return &F->frames[F->depth - 1];
}

int aether_try_depth(void) {
    return t_frames.depth;
}

/* A `try` caught an interruption of a library call (#2956, aether_exec.c):
 * it passes it on after its own cleanup (aether_exec_reraise). Here, where
 * every program links it, and not in aether_exec.c. */
int aether_exec_interrupting(void) {
    return t_frames.interrupting != 0;
}

/* aether_exec.h (#3404). The execution it targets is the innermost one
 * this code runs in (an interruption is raised only there); none left
 * running here (it already ended) takes nothing. */
void aether_exec_defer_interruption(void) {
    AetherFrames* F = &t_frames;
    int why = F->interrupting;
    F->interrupting = 0;
    if (!why || F->exec_depth <= F->exec_floor) return;
    AetherExecRecord* x = &F->exec[F->exec_depth - 1];
    if (!x->stop) x->stop = why;
}

static void journal_at(const void* p, AetherUnwindFree free_fn, int depth);

void aether_unwind_track(const void* p, AetherUnwindFree free_fn) {
    if (t_frames.depth == 0 || !p || !free_fn) return;
    journal_at(p, free_fn, t_frames.depth);
}

void aether_unwind_track_place(const void* place, const void* owned, AetherUnwindFree release) {
    if (t_frames.depth == 0 || !place || !release) return;
    journal_at(place, release, t_frames.depth);
    for (int i = t_frames.journal_count - 1; i >= 0; i--) {
        if (t_frames.journal[i].ptr == place) {
            t_frames.journal[i].owned = owned;
            t_frames.journal[i].place = 1;
            return;
        }
    }
}

static void journal_at(const void* p, AetherUnwindFree free_fn, int depth) {
    // Re-tracking an already-journaled pointer updates in place: the
    // ownership handoff shapes (callee returns, caller re-arms its own
    // defer) must never accumulate two entries for one allocation.
    for (int i = t_frames.journal_count - 1; i >= 0; i--) {
        if (t_frames.journal[i].ptr == p) {
            t_frames.journal[i].free_fn = free_fn;
            t_frames.journal[i].depth = depth;
            return;
        }
    }
    if (t_frames.journal_count == t_frames.journal_capacity) {
        int cap = t_frames.journal_capacity ? t_frames.journal_capacity * 2 : 32;
        AetherUnwindEntry* grown =
            (AetherUnwindEntry*)realloc(t_frames.journal,
                                        (size_t)cap * sizeof(AetherUnwindEntry));
        if (!grown) return;  // OOM: skip journaling; worst case is the old leak
        t_frames.journal = grown;
        t_frames.journal_capacity = cap;
    }
    t_frames.journal[t_frames.journal_count].ptr = p;
    t_frames.journal[t_frames.journal_count].owned = NULL;
    t_frames.journal[t_frames.journal_count].free_fn = free_fn;
    t_frames.journal[t_frames.journal_count].depth = depth;
    t_frames.journal[t_frames.journal_count].place = 0;
    t_frames.journal[t_frames.journal_count].draining = 0;
    t_frames.journal_count++;
}

void aether_unwind_forget(const void* p) {
    if (t_frames.journal_count == 0 || !p) return;
    // Scan newest-first: frees are overwhelmingly LIFO.
    for (int i = t_frames.journal_count - 1; i >= 0; i--) {
        if (t_frames.journal[i].ptr == p) {
            t_frames.journal[i] = t_frames.journal[t_frames.journal_count - 1];
            t_frames.journal_count--;
            return;
        }
    }
}

int aether_unwind_journal_size(void) {
    return t_frames.journal_count;
}

// Free every entry tagged at the innermost depth and remove it. Runs
// from aether_panic() before the longjmp, while the allocations'
// owning stack frames are still intact (the entries themselves are
// TLS, so intactness only matters for the free functions, which take
// the raw pointer and touch nothing else).
//
// It allocates nothing (#2956): a panic may be the interruption of a call
// whose allocation just failed. The entries to release are marked first;
// then, newest first, each is taken out of the journal before its release
// runs, since a release may forget or track other entries. An entry a
// release forgets is not released again (it used to be, from a copy of the
// journal the drain had taken); one a release tracks is not marked, and
// stays in the journal for the frame that receives it.
void aether_unwind_drain_current(void) {
    int n = 0;
    for (int i = 0; i < t_frames.journal_count; i++) {
        if (t_frames.journal[i].depth >= t_frames.depth) {
            t_frames.journal[i].draining = 1;
            n++;
        }
    }
    /* Newest first, as scope exits run: a deferred statement still sees the
     * locals declared before it. */
    while (n > 0) {
        int i = t_frames.journal_count - 1;
        while (i >= 0 && !t_frames.journal[i].draining) i--;
        if (i < 0) break;   /* the rest were forgotten by a release */
        AetherUnwindEntry e = t_frames.journal[i];
        memmove(&t_frames.journal[i], &t_frames.journal[i + 1],
                (size_t)(t_frames.journal_count - i - 1) * sizeof(AetherUnwindEntry));
        t_frames.journal_count--;
        n--;
        if (!e.place) {
            e.free_fn(e.ptr);
            continue;
        }
        const void* volatile* slot = (const void* volatile*)e.ptr;
        volatile int* owned = (volatile int*)e.owned;
        const void* v = *slot;
        if (!v || (owned && !*owned)) continue;
        if (owned) *owned = 0;
        *slot = NULL;
        e.free_fn(v);
    }
}

// Normal frame exit: surviving entries of the popped depth are owned by
// C locals that are still live, so they move under the parent frame's
// protection. With no parent frame nothing can unwind past them; their
// deferred frees run normally, so the entries just leave the journal.
void aether_unwind_exit_frame(void) {
    if (t_frames.depth <= 1) {
        t_frames.journal_count = 0;
        return;
    }
    for (int i = 0; i < t_frames.journal_count; i++) {
        if (t_frames.journal[i].depth >= t_frames.depth) {
            t_frames.journal[i].depth = t_frames.depth - 1;
        }
    }
}

typedef void (*AetherTeardown)(void* obj);

static AETHER_TLS_SHARED void** tls_teardown_queue = NULL;
static AETHER_TLS_SHARED int tls_teardown_count = 0;
static AETHER_TLS_SHARED int tls_teardown_capacity = 0;
static AETHER_TLS_SHARED int tls_teardown_running = 0;

void aether_teardown(void* obj) {
    if (tls_teardown_running) {
        if (tls_teardown_count == tls_teardown_capacity) {
            int cap = tls_teardown_capacity ? tls_teardown_capacity * 2 : 16;
            void** q = (void**)realloc(tls_teardown_queue, (size_t)cap * sizeof(void*));
            if (!q) {
                /* No memory to queue it (#2956): torn down here instead, on
                 * the stack. The process used to stop, and a library call
                 * could not end with its outcome. */
                (*(AetherTeardown*)obj)(obj);
                return;
            }
            tls_teardown_queue = q;
            tls_teardown_capacity = cap;
        }
        tls_teardown_queue[tls_teardown_count++] = obj;
        return;
    }
    tls_teardown_running = 1;
    (*(AetherTeardown*)obj)(obj);
    while (tls_teardown_count > 0) {
        void* next = tls_teardown_queue[--tls_teardown_count];
        (*(AetherTeardown*)next)(next);
    }
    tls_teardown_running = 0;
}

void aether_unwind_thread_cleanup(void) {
    free(t_frames.journal);
    t_frames.journal = NULL;
    t_frames.journal_count = 0;
    t_frames.journal_capacity = 0;
    free(tls_teardown_queue);
    tls_teardown_queue = NULL;
    tls_teardown_capacity = 0;
}
