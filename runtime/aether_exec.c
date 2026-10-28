/* aether_exec.c: execution frames and outcomes (#2955, #2956). See
 * aether_exec.h.
 *
 * What an execution may change on this thread, and how it gets back:
 * - the deadline: a host service a running execution calls sets one for
 *   the executions it enters (aether_set_call_deadline, while one runs,
 *   lands here), and the running execution keeps its own; a nested
 *   execution's deadline is the outer one's again when it returns. At the
 *   outermost level the host owns the deadline and reads it after the
 *   call, as before;
 * - the caller info: kept per execution by aether_host.c, which this
 *   tells when an execution returns;
 * - the sandbox levels: back to their depth at entry (a panic has already
 *   left the levels pushed inside the frame, aether_panic.c).
 * Nothing done before a failure is rolled back: host effects, module state,
 * messages sent.
 *
 * The cost of a call that does not fail is the floor a catchable panic
 * needs: the stub's context save (__builtin_setjmp, aether_panic.h) and a
 * frame where a panic finds it, one thread-local block (aether_frames.h)
 * entered and left. The rest is read only once something asks for it: the
 * deadline when executions nest or one was ever armed, the sandbox depth
 * when some thread has a level, the caller info when a host service
 * changed it during the call. */

#include "aether_exec.h"
#include "aether_resource_caps.h"
#include "aether_host.h"
#include "aether_sandbox.h"
#include "actors/aether_frames.h"
#include "actors/aether_unwind.h"
#include "utils/aether_compiler.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The two the public header (libaether.h) declares: exported however the
 * runtime is built. */
#if defined(__GNUC__) || defined(__clang__)
#  define AETHER_EXEC_API __attribute__((visibility("default")))
#else
#  define AETHER_EXEC_API
#endif

#ifdef AETHER_HAS_SANDBOX
/* Some thread has a sandbox level in force (aether_sandbox.h). Unresolved,
 * this copy has pushed nothing, so this thread's levels here are none. */
static inline int sandbox_any(void) {
    atomic_int* in_force = atomic_load_explicit(&aether_sandbox_in_force, memory_order_acquire);
    return in_force && atomic_load_explicit(in_force, memory_order_relaxed) != 0;
}
#endif

int aether_exec_depth(void) {
    return aether_frames.exec_depth;
}

void aether_exec_mark_view(int depth) {
    AetherFrames* F = &aether_frames;
    if (depth >= 1 && depth <= F->exec_depth) F->exec[depth - 1].has_view = 1;
}

void aether_exec_set_next_deadline(int64_t ms) {
    AetherFrames* F = &aether_frames;
    if (F->exec_depth <= 0) {
        aether_caps_set_deadline_ms(ms);
        return;
    }
    AetherExecRecord* running = &F->exec[F->exec_depth - 1];
    AetherDeadlineState s = aether_caps_deadline_for_ms(ms);
    running->next_at_ns = s.at_ns;
    running->next_tripped = 0;
    running->next_set = 1;
    if (ms > 0) aether_caps_armed = 1;
}

static inline AetherJmpFrame* exec_push(AetherFrames* F, void** buf) {
    if (F->depth >= AETHER_PANIC_MAX_DEPTH) {
        fprintf(stderr, "aether: try/catch and executions nested deeper than %d on one thread, aborting\n",
                AETHER_PANIC_MAX_DEPTH);
        abort();
    }
    int d = F->exec_depth;
    AetherExecRecord* x = &F->exec[d];
    if (d > 0) {
        /* Nested: the outer execution's deadline comes back when this one
         * returns, and the one a host service set for it applies. */
        AetherDeadlineState s;
        aether_caps_deadline_save(&s);
        x->deadline_at_ns = s.at_ns;
        x->deadline_tripped = s.tripped;
        AetherExecRecord* outer = &F->exec[d - 1];
        if (outer->next_set) {
            AetherDeadlineState n = { outer->next_at_ns, outer->next_tripped };
            aether_caps_deadline_restore(&n);
        }
    }
#ifdef AETHER_HAS_SANDBOX
    x->sandbox_depth = sandbox_any() ? aether_sandbox_depth() : 0;
#else
    x->sandbox_depth = 0;
#endif
    x->next_set = 0;
    x->has_view = 0;
    F->exec_depth = d + 1;
    AetherJmpFrame* f = &F->frames[F->depth++];
    /* reason and reason_release are written by the panic that targets
     * this frame, before it jumps (aether_panic.c); nothing else reads
     * them. */
    f->exec_buf = buf;
    return f;
}

AetherJmpFrame* aether_exec_enter(void) {
    return exec_push(&aether_frames, NULL);
}

#if AETHER_EXEC_BUILTIN_SJLJ
void aether_exec_enter_at(void** buf) {
    (void)exec_push(&aether_frames, buf);
}
#endif

static void set_text(AetherFrames* F, const char* text) {
    if (!text) text = "";
    size_t n = strlen(text);
    if (n >= sizeof(F->outcome_text)) n = sizeof(F->outcome_text) - 1;
    memcpy(F->outcome_text, text, n);
    F->outcome_text[n] = '\0';
}

static inline void exec_finish(AetherFrames* F, int outcome) {
    /* Its panic frame, as aether_try_pop takes one. */
    if (F->journal_count) aether_unwind_exit_frame();
    F->depth--;
    int leaving = F->exec_depth;
    F->exec_depth--;
    AetherExecRecord* x = &F->exec[F->exec_depth];
    /* A nested execution: the outer one's deadline, trip flag and all. */
    if (F->exec_depth > 0) {
        AetherDeadlineState s = { x->deadline_at_ns, x->deadline_tripped };
        aether_caps_deadline_restore(&s);
    }
#ifdef AETHER_HAS_SANDBOX
    if (sandbox_any()) aether_sandbox_restore(x->sandbox_depth);
#endif
    if (x->has_view) aether_caller_leave(leaving);
    F->outcome = outcome;
}

void aether_exec_leave(void) {
    AetherFrames* F = &aether_frames;
    /* The trip flag is read only once some deadline was ever armed. */
    if (aether_caps_armed && aether_caps_deadline_flag()) {
        set_text(F, "the call's deadline passed");
        exec_finish(F, AETHER_DEADLINE);
        return;
    }
    exec_finish(F, AETHER_OK);
}

void aether_exec_failed(void) {
    AetherFrames* F = &aether_frames;
    /* The panic reached this execution's frame: the innermost one. */
    AetherJmpFrame* f = &F->frames[F->depth - 1];
    set_text(F, aether_panic_reason_text(f->reason));
    /* A reason built at run time belongs to whoever catches it: this frame. */
    if (f->reason_release) {
        void (*release)(const void*) = f->reason_release;
        f->reason_release = NULL;
        release(f->reason);
    }
    exec_finish(F, AETHER_PANICKED);
}

AETHER_EXEC_API int aether_last_outcome(void) {
    return aether_frames.outcome;
}

AETHER_EXEC_API const char* aether_last_outcome_text(void) {
    /* Written only for a failure: an OK call leaves the last text, unread. */
    return aether_frames.outcome == AETHER_OK ? "" : aether_frames.outcome_text;
}

/* The stub of an export nothing can end from outside its code (a frameless
 * one, codegen.c lib_export_frameless): its call ended OK. */
void aether_exec_ok(void) {
    aether_frames.outcome = AETHER_OK;
}

void aether_exec_note_outcome(int outcome, const char* text) {
    AetherFrames* F = &aether_frames;
    F->outcome = outcome;
    set_text(F, outcome == AETHER_OK ? "" : text);
}
