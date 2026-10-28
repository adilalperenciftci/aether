/**
 * A step runs in its own context, and gives the enclosing step's back
 * (#3389; runtime/actors/aether_step_barrier.h has the rule).
 *
 * A send to an idle actor of the same core steps it inline, inside the
 * sender's handler. What the inner step changed of the thread's per-step
 * state stayed changed for the rest of the outer handler: the in-step flag
 * and the actor id the signal handler reads were 0 and -1 after it, so a
 * fault in the rest of the outer handler was not recovered as a panic.
 */

#include "test_harness.h"
#include "../../runtime/actors/actor_state_machine.h"
#include "../../runtime/actors/aether_send_message.h"
#include "../../runtime/scheduler/multicore_scheduler.h"
#include "../../runtime/actors/aether_panic.h"
#include "../../runtime/utils/aether_thread.h"
#include <stdatomic.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
#define sc_sleep_ms(ms) Sleep(ms)
#else
#include <unistd.h>
#define sc_sleep_ms(ms) usleep((ms) * 1000)
#endif

typedef struct {
    int type;   // the message id comes first, as in every typed payload
    int value;
} ScMsg;

typedef struct {
    AETHER_ACTOR_BASE_FIELDS
    ActorBase* tell;          // sent a payload message (stepped inline) when set
    atomic_int got;
    atomic_int in_step_after; // g_aether_in_actor_step once the send returned
    atomic_int id_after;      // g_aether_current_actor_id then
    atomic_int done;
} ScActor;

static void sc_step(ScActor* self) {
    Message msg;
    if (!mailbox_receive(&self->mailbox, &msg)) {
        atomic_store_explicit(&self->active, 0, memory_order_relaxed);
        return;
    }
    aether_reply_slot_set(msg._reply_slot);
    if (msg.payload_ptr) aether_free_message(msg.payload_ptr);
    atomic_fetch_add(&self->got, 1);
    if (self->tell) {
        ScMsg m = { 1, 0 };
        aether_send_message(self->tell, &m, sizeof m);
        atomic_store(&self->in_step_after, g_aether_in_actor_step);
        atomic_store(&self->id_after, g_aether_current_actor_id);
        atomic_store(&self->done, 1);
    }
    atomic_store_explicit(&self->active, self->mailbox.count > 0, memory_order_relaxed);
}

static ScActor* sc_actor(int core) {
    ScActor* a = calloc(1, sizeof(ScActor));
    static int next_id = 9700;
    a->id = next_id++;
    a->step = (void (*)(void*))sc_step;
    atomic_init(&a->assigned_core, -1);
    atomic_init(&a->migrate_to, -1);
    atomic_init(&a->reply_slot, NULL);
    atomic_flag_clear_explicit(&a->step_lock, memory_order_relaxed);
    mailbox_init(&a->mailbox);
    scheduler_register_actor((ActorBase*)a, core);
    return a;
}

static int sc_wait(atomic_int* v, int want, int limit_ms) {
    for (int w = 0; w < limit_ms && atomic_load(v) < want; w++) sc_sleep_ms(1);
    return atomic_load(v) >= want;
}

/* A on core 0 sends to B, idle on core 0: B is stepped inside A's
 * handler. After the send A is still the actor stepping. */
TEST_CATEGORY(step_context_in_step_flags_come_back, TEST_CATEGORY_RUNTIME) {
    scheduler_init(1);
    ScActor* b = sc_actor(0);
    ScActor* a = sc_actor(0);
    a->tell = (ActorBase*)b;
    scheduler_start();

    ScMsg m = { 1, 0 };
    aether_send_message(a, &m, sizeof m);
    int done = sc_wait(&a->done, 1, 6000);
    int stepped = sc_wait(&b->got, 1, 2000);
    scheduler_shutdown();
    scheduler_cleanup();

    ASSERT_TRUE(done);
    ASSERT_TRUE(stepped);
    ASSERT_EQ(1, atomic_load(&a->in_step_after));
    ASSERT_EQ(a->id, atomic_load(&a->id_after));
    free(a);
    free(b);
}
