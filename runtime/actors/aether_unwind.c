// Allocation journal: deterministic heap cleanup on panic unwind.
// See aether_unwind.h for the invariant and the link-surface warning
// that keeps this out of aether_panic.c.

#include "aether_unwind.h"
#include "../utils/aether_compiler.h"
#include "aether_frames.h"
#include <stdlib.h>

/* An entry is a value (`free_fn(ptr)` on a drain) or a place (#2923): `ptr`
 * is the address of a slot holding a value, `owned` the address of the flag
 * that says the slot owns it (NULL: it owns whatever it holds), and a drain
 * releases what the slot holds then, leaving it empty. */
typedef struct AetherUnwindEntry {
    const void* ptr;
    const void* owned;
    AetherUnwindFree free_fn;
    int depth;
    int place;
} AetherUnwindEntry;


/* The per-thread frames block (aether_frames.h), with the journal in it.
 * AETHER_TLS_SHARED, not AETHER_TLS: this object is pulled into both
 * executables and --emit=lib shared objects (the emitted prologue
 * references the track/forget symbols from every program). Initial-Exec
 * TLS relocations do not work inside shared objects; Global-Dynamic works
 * in both contexts. Defined here rather than in aether_panic.c, so that
 * journaling pulls in no more than this file. */
AETHER_TLS_SHARED AetherFrames aether_frames;

static void journal_at(const void* p, AetherUnwindFree free_fn, int depth);

void aether_unwind_track(const void* p, AetherUnwindFree free_fn) {
    if (aether_frames.depth == 0 || !p || !free_fn) return;
    journal_at(p, free_fn, aether_frames.depth);
}

void aether_unwind_track_place(const void* place, const void* owned, AetherUnwindFree release) {
    if (aether_frames.depth == 0 || !place || !release) return;
    journal_at(place, release, aether_frames.depth);
    for (int i = aether_frames.journal_count - 1; i >= 0; i--) {
        if (aether_frames.journal[i].ptr == place) {
            aether_frames.journal[i].owned = owned;
            aether_frames.journal[i].place = 1;
            return;
        }
    }
}

static void journal_at(const void* p, AetherUnwindFree free_fn, int depth) {
    // Re-tracking an already-journaled pointer updates in place: the
    // ownership handoff shapes (callee returns, caller re-arms its own
    // defer) must never accumulate two entries for one allocation.
    for (int i = aether_frames.journal_count - 1; i >= 0; i--) {
        if (aether_frames.journal[i].ptr == p) {
            aether_frames.journal[i].free_fn = free_fn;
            aether_frames.journal[i].depth = depth;
            return;
        }
    }
    if (aether_frames.journal_count == aether_frames.journal_capacity) {
        int cap = aether_frames.journal_capacity ? aether_frames.journal_capacity * 2 : 32;
        AetherUnwindEntry* grown =
            (AetherUnwindEntry*)realloc(aether_frames.journal,
                                        (size_t)cap * sizeof(AetherUnwindEntry));
        if (!grown) return;  // OOM: skip journaling; worst case is the old leak
        aether_frames.journal = grown;
        aether_frames.journal_capacity = cap;
    }
    aether_frames.journal[aether_frames.journal_count].ptr = p;
    aether_frames.journal[aether_frames.journal_count].owned = NULL;
    aether_frames.journal[aether_frames.journal_count].free_fn = free_fn;
    aether_frames.journal[aether_frames.journal_count].depth = depth;
    aether_frames.journal[aether_frames.journal_count].place = 0;
    aether_frames.journal_count++;
}

void aether_unwind_forget(const void* p) {
    if (aether_frames.journal_count == 0 || !p) return;
    // Scan newest-first: frees are overwhelmingly LIFO.
    for (int i = aether_frames.journal_count - 1; i >= 0; i--) {
        if (aether_frames.journal[i].ptr == p) {
            aether_frames.journal[i] = aether_frames.journal[aether_frames.journal_count - 1];
            aether_frames.journal_count--;
            return;
        }
    }
}

int aether_unwind_journal_size(void) {
    return aether_frames.journal_count;
}

// Free every entry tagged at the innermost depth and remove it. Runs
// from aether_panic() before the longjmp, while the allocations'
// owning stack frames are still intact (the entries themselves are
// TLS, so intactness only matters for the free functions, which take
// the raw pointer and touch nothing else).
//
// The entries are taken off the journal before any release runs: a release
// may forget or track other entries, which must not move under the loop.
void aether_unwind_drain_current(void) {
    int n = 0;
    for (int i = 0; i < aether_frames.journal_count; i++)
        if (aether_frames.journal[i].depth >= aether_frames.depth) n++;
    if (n == 0) return;
    AetherUnwindEntry* drained = (AetherUnwindEntry*)malloc((size_t)n * sizeof(AetherUnwindEntry));
    int w = 0, d = 0;
    for (int i = 0; i < aether_frames.journal_count; i++) {
        if (aether_frames.journal[i].depth < aether_frames.depth) {
            aether_frames.journal[w++] = aether_frames.journal[i];
        } else if (drained) {
            drained[d++] = aether_frames.journal[i];
        }
    }
    aether_frames.journal_count = w;
    /* Newest first, as scope exits run: a deferred statement still sees the
     * locals declared before it. */
    for (int i = d - 1; i >= 0; i--) {
        AetherUnwindEntry* e = &drained[i];
        if (!e->place) {
            e->free_fn(e->ptr);
            continue;
        }
        const void* volatile* slot = (const void* volatile*)e->ptr;
        volatile int* owned = (volatile int*)e->owned;
        const void* v = *slot;
        if (!v || (owned && !*owned)) continue;
        if (owned) *owned = 0;
        *slot = NULL;
        e->free_fn(v);
    }
    free(drained);
}

// Normal frame exit: surviving entries of the popped depth are owned by
// C locals that are still live, so they move under the parent frame's
// protection. With no parent frame nothing can unwind past them; their
// deferred frees run normally, so the entries just leave the journal.
void aether_unwind_exit_frame(void) {
    if (aether_frames.depth <= 1) {
        aether_frames.journal_count = 0;
        return;
    }
    for (int i = 0; i < aether_frames.journal_count; i++) {
        if (aether_frames.journal[i].depth >= aether_frames.depth) {
            aether_frames.journal[i].depth = aether_frames.depth - 1;
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
            if (!q) abort();
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
    free(aether_frames.journal);
    aether_frames.journal = NULL;
    aether_frames.journal_count = 0;
    aether_frames.journal_capacity = 0;
    free(tls_teardown_queue);
    tls_teardown_queue = NULL;
    tls_teardown_capacity = 0;
}
