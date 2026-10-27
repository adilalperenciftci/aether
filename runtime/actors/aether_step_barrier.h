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
 * The step context (the ask being handled, the actor stepping) is the
 * thread's, and a step can run inside another: a send steps an idle actor of
 * the same core inline while the sender's handler is still running, its ask
 * not yet answered, and a cooperative ask polls until its reply. Each step
 * starts with no ask in hand and gives the enclosing one its context back
 * when it ends. Neither variable changes between the sigsetjmp and a longjmp
 * back to it, so both are intact on the panic path.
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

static inline void aether_step_barrier(ActorBase* actor,
                                       void (*finalize)(ActorBase*),
                                       void (*fail_slot)(void* slot, int why),
                                       void (*after_step)(ActorBase*)) {
    void* outer_slot = g_current_reply_slot;
    void* outer_actor = g_current_step_actor;
    g_current_reply_slot = NULL;

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
        g_current_reply_slot = outer_slot;
        g_current_step_actor = outer_actor;
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

    aether_fire_death_hook(actor->id, reason);
    /* A heap-built panic message (aether_panic_owned) belongs to whoever
     * caught it, here this barrier. The hook has seen it; release it. */
    if (reason_release) reason_release(reason);
    g_current_reply_slot = outer_slot;
    g_current_step_actor = outer_actor;
}

#endif /* AETHER_STEP_BARRIER_H */
