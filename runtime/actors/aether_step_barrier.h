#ifndef AETHER_STEP_BARRIER_H
#define AETHER_STEP_BARRIER_H

/* One step of an actor inside the panic barrier, shared by the multicore and
 * the cooperative scheduler (#2974).
 *
 * If the handler calls aether_panic() or takes a caught signal, the barrier
 * unwinds: the actor ends (its PANICKED bit, the panic's reason unless
 * something ended it first), the message its handler was running on and the
 * ask it held are dropped and failed, the scheduler finalizes its death
 * (drains what waits for it and tells its watchers), and the C death hook
 * fires. Otherwise, after the step: an ask the handler took and left
 * unanswered fails, a stop() or a kill that came while it ran is finalized,
 * and the scheduler's own after-step work runs.
 *
 * A step runs in its own context, whatever thread runs it and whatever
 * runs below it there (#3389). A step can run inside another: a send steps
 * an idle actor of the same core inline while the sender's handler is still
 * running, and a cooperative ask polls until its reply. The rule, for every
 * step and both of its ends:
 *
 *   - at entry, the step puts aside the per-thread context of the code it
 *     runs inside, and starts with none of it;
 *   - at exit, normal or by panic, it gives that context back as it was;
 *   - its panic, and its end, undo only what the step itself made.
 *
 * The context, part by part:
 *   - the ask in hand (g_current_reply_slot) and the actor stepping
 *     (g_current_step_actor): a handler that sends, or asks, before it
 *     replies still answers its own asker;
 *   - the in-step flags (g_aether_in_actor_step, g_aether_current_actor_id):
 *     the outer handler keeps its signal recovery after an inner step;
 *   - a supervisor's restart claim, the reborn block and the spawn brackets
 *     (aether_supervision.c): a nested step's spawn takes no claimed block
 *     and is no factory's child, and its panic undoes no enclosing claim;
 *   - the sandbox levels in force on the thread, in this runtime copy and
 *     every other it shares the count with (aether_sandbox.c, #3393): a
 *     receiver stepped inside an enforce block is checked as it is on a
 *     thread of its own, against the levels it pushes itself and no other,
 *     and the block's levels are in force again when the send returns.
 *
 * Each part costs a step only when some thread holds that kind of context:
 * it is put aside behind a load of a global that says so
 * (g_aether_spawn_watch for the claim; for the levels, the count of threads
 * with one, through aether_sandbox_in_force); the ask and the actor are two
 * thread-local words, and the in-step flags are restored from what the
 * step read when it set them. Neither the locals holding what was put aside
 * nor the variables change between the sigsetjmp and a longjmp back to it,
 * so all of it is intact on the panic path.
 *
 * The scheduler's parts are passed as functions it defines static: the
 * compiler sees them at the call and inlines the whole. The caller has
 * checked that the actor has a step and is not dead, and holds what it holds
 * to step it (a core's step lock). The step lock is not released here, on
 * either path (#2163): the caller took it and clears it.
 *
 * Where the target has no setjmp (wasi), AETHER_SIGSETJMP always takes the
 * first arm and a panic aborts the program (aether_panic.h). */

#include "aether_panic.h"
#include "../scheduler/multicore_scheduler.h"
#include "../utils/aether_trace.h"

extern AETHER_TLS void* g_current_reply_slot;
extern AETHER_TLS void* g_current_step_actor;

/* The sandbox's part (aether_panic.c's pointers, which aether_sandbox.c sets
 * when it first looks for the runtime copies): the threads with a level in
 * force, and how this thread's levels are put aside and given back. */
extern atomic_int* _Atomic aether_sandbox_in_force;
extern int (*_Atomic aether_step_sandbox_hide)(int saved[2]);
extern void (*_Atomic aether_step_sandbox_show)(const int saved[2]);

/* What a step put aside, to give back when it ends. */
typedef struct {
    void* reply_slot;
    void* step_actor;
    int in_step;
    int actor_id;
    int spawn_hid;
    int sandbox_hid;
    AetherSpawnAside spawn;
    int sandbox[2];
} AetherStepAside;

static inline void aether_step_put_aside(AetherStepAside* s) {
    s->reply_slot = g_current_reply_slot;
    s->step_actor = g_current_step_actor;
    g_current_reply_slot = NULL;
    s->in_step = g_aether_in_actor_step;
    s->actor_id = s->in_step ? g_aether_current_actor_id : -1;
    s->spawn_hid = unlikely(atomic_load_explicit(&g_aether_spawn_watch, memory_order_relaxed) != 0) &&
                   aether_spawn_put_aside(&s->spawn);
    s->sandbox_hid = 0;
    atomic_int* in_force = atomic_load_explicit(&aether_sandbox_in_force, memory_order_acquire);
    if (unlikely(in_force != NULL) && unlikely(atomic_load_explicit(in_force, memory_order_relaxed) != 0)) {
        int (*hide)(int saved[2]) = atomic_load_explicit(&aether_step_sandbox_hide, memory_order_relaxed);
        s->sandbox_hid = hide && hide(s->sandbox);
    }
}

static inline void aether_step_give_back(const AetherStepAside* s) {
    if (unlikely(s->sandbox_hid))
        atomic_load_explicit(&aether_step_sandbox_show, memory_order_relaxed)(s->sandbox);
    if (unlikely(s->spawn_hid)) aether_spawn_give_back(&s->spawn);
    g_aether_in_actor_step = s->in_step;
    g_aether_current_actor_id = s->actor_id;
    g_current_reply_slot = s->reply_slot;
    g_current_step_actor = s->step_actor;
}

static inline void aether_step_barrier(ActorBase* actor,
                                       void (*finalize)(ActorBase*),
                                       void (*fail_slot)(void* slot, int why),
                                       void (*after_step)(ActorBase*)) {
    AetherStepAside aside;
    aether_step_put_aside(&aside);

    AetherJmpFrame* f = aether_try_push();
    if (AETHER_SIGSETJMP(f->buf, 1) == 0) {
        g_aether_in_actor_step = 1;
        g_aether_current_actor_id = actor->id;
        AETHER_TRACE_EVENT(AE_TRACE_STEP_BEGIN, actor->id, -1, -1);
        actor->step(actor);
        AETHER_TRACE_EVENT(AE_TRACE_STEP_END, actor->id, -1, -1);
        g_aether_in_actor_step = 0;
        g_aether_current_actor_id = -1;
        aether_try_pop();
        /* A handler that took an ask and returned without replying: no
         * reply can come, since a reply answers the ask its own step took.
         * Its asker learns that now, not at its timeout. */
        if (g_current_reply_slot) {
            void* held = g_current_reply_slot;
            g_current_reply_slot = NULL;
            fail_slot(held, AETHER_ASK_NO_REPLY);
        }
        /* Ended while the handler ran (#2974): its stop(), or a kill or a
         * linked actor's death from elsewhere, takes effect now that the
         * handler has returned, so no Down is sent while it runs. A release
         * ends it by its own path. */
        int ended = atomic_load_explicit(&actor->dead, memory_order_acquire);
        if (unlikely(ended != 0)) {
            if (!(ended & AETHER_ACTOR_RELEASED)) finalize(actor);
        } else if (after_step) {
            after_step(actor);
        }
        aether_step_give_back(&aside);
        return;
    }

    // Unwound via panic or signal.
    const char* reason = f->reason;
    void (*reason_release)(const void*) = f->reason_release;
    g_aether_in_actor_step = 0;
    g_aether_current_actor_id = -1;
    aether_try_pop();

    // A bit, not a store: a release may be setting its own bit meanwhile.
    // The reason is the panic's unless something ended the actor first.
    aether_actor_claim_end(actor, aether_panic_reason_text(reason), AETHER_ACTOR_PANICKED);
    atomic_store_explicit(&actor->active, 0, memory_order_release);

    /* The message its handler was running on (#3142): the release that
     * follows the handler did not run, so what the message owns and its
     * payload go here, as a dropped message's do. */
    if (actor->step_payload) {
        Message held = {0};
        held.type = actor->step_type;
        held.payload_ptr = actor->step_payload;
        actor->step_payload = NULL;
        aether_message_drop(actor, &held);
    }

    /* The ask it was handling, if it had not replied (#3151): its asker
     * learns now that no reply is coming, instead of at its timeout. */
    if (g_current_reply_slot) {
        void* held = g_current_reply_slot;
        g_current_reply_slot = NULL;
        fail_slot(held, AETHER_ASK_DIED);
    }

    // What waits for it is dropped and credited, and its watchers told.
    finalize(actor);
    // A restart in place its handler had begun is undone (#2974), and the
    // spawn brackets it opened are closed: its own, never an enclosing
    // step's, which were put aside (#3389).
    aether_spawn_step_panicked();

    aether_fire_death_hook(actor->id, reason);
    /* A heap-built panic message (aether_panic_owned) belongs to whoever
     * caught it, here this barrier. The hook has seen it; release it. */
    if (reason_release) reason_release(reason);
    aether_step_give_back(&aside);
}

#endif /* AETHER_STEP_BARRIER_H */
