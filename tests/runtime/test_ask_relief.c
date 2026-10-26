/**
 * A core whose thread waits in an ask keeps its work moving (#3197).
 *
 * An ask made in a handler blocks that core's scheduler thread until the
 * reply. Its queued messages were not delivered and its other actors not
 * stepped meanwhile, so an actor elsewhere that, answering, asked one of
 * them waited out its timeout, and so did every actor of the core. The
 * waiting thread now relieves its core: it delivers what is queued for its
 * actors and moves those with work to a core that runs them (the core
 * waiting on that actor, or an idle one). An actor with more queued than its
 * mailbox holds stays until the ask ends (#3241).
 *
 * The actors are registered on the cores the cases need, which the
 * scheduler keeps: nothing here sends from one core to another outside an
 * ask, which gathers nothing, and no core idles long enough to steal.
 */

#include "test_harness.h"
#include "../../runtime/actors/actor_state_machine.h"
#include "../../runtime/actors/aether_send_message.h"
#include "../../runtime/scheduler/multicore_scheduler.h"
#include "../../runtime/utils/aether_thread.h"
#include <stdatomic.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
#define relief_sleep_ms(ms) Sleep(ms)
#else
#include <unistd.h>
#define relief_sleep_ms(ms) usleep((ms) * 1000)
#endif

typedef struct {
    int type;   // the message id comes first, as in every typed payload
    int value;
} ReliefMsg;

typedef struct {
    AETHER_ACTOR_BASE_FIELDS
    ActorBase* ask;        // asked on every message when set
    ActorBase* watch;      // its count is read when the ask returns
    int pause_ms;          // slept before replying
    atomic_int got;        // messages handled
    atomic_int result;     // what the ask returned
    atomic_int watched;    // `watch`'s count when it did
    atomic_long took_ms;   // how long it took
    atomic_int done;
} ReliefActor;

static void relief_step(ReliefActor* self) {
    Message msg;
    if (!mailbox_receive(&self->mailbox, &msg)) {
        atomic_store_explicit(&self->active, 0, memory_order_relaxed);
        return;
    }
    aether_reply_slot_set(msg._reply_slot);
    if (msg.payload_ptr) aether_free_message(msg.payload_ptr);
    atomic_fetch_add(&self->got, 1);

    int value = 42;
    if (self->ask) {
        ReliefMsg q = { 1, 0 };
        uint64_t t0 = aether_now_ns();
        int* r = (int*)scheduler_ask_message(self->ask, &q, sizeof q, 3000);
        atomic_store(&self->took_ms, (long)((aether_now_ns() - t0) / 1000000ULL));
        value = r ? *r + 1 : -1000;
        free(r);
        if (self->watch) atomic_store(&self->watched, atomic_load(&((ReliefActor*)self->watch)->got));
        atomic_store(&self->result, value);
        atomic_store(&self->done, 1);
    }
    if (self->pause_ms) relief_sleep_ms(self->pause_ms);
    scheduler_reply((ActorBase*)self, &value, sizeof value);   // no asker: nothing
    atomic_store_explicit(&self->active, self->mailbox.count > 0, memory_order_relaxed);
}

static ReliefActor* relief_actor(int core) {
    ReliefActor* a = calloc(1, sizeof(ReliefActor));
    static int next_id = 9000;
    a->id = next_id++;
    a->step = (void (*)(void*))relief_step;
    atomic_init(&a->assigned_core, -1);
    atomic_init(&a->migrate_to, -1);
    atomic_init(&a->reply_slot, NULL);
    atomic_flag_clear_explicit(&a->step_lock, memory_order_relaxed);
    mailbox_init(&a->mailbox);
    scheduler_register_actor((ActorBase*)a, core);
    return a;
}

static void relief_send(ReliefActor* a) {
    ReliefMsg m = { 1, 0 };
    aether_send_message(a, &m, sizeof m);
}

static int relief_wait_done(ReliefActor* a, int limit_ms) {
    for (int w = 0; w < limit_ms && !atomic_load(&a->done); w++) relief_sleep_ms(1);
    return atomic_load(&a->done);
}

/* The chain of the issue: A on core 0 asks B on core 1, and B, answering,
 * asks C, which is on core 0 too. C's message waited in core 0's queue
 * while core 0 waited for B: both asks timed out. */
static void test_ask_relief_chain_back_to_waiting_core(void) {
    scheduler_init(2);
    ReliefActor* c = relief_actor(0);
    ReliefActor* b = relief_actor(1);
    ReliefActor* a = relief_actor(0);
    b->ask = (ActorBase*)c;
    a->ask = (ActorBase*)b;
    scheduler_start();

    relief_send(a);
    int done = relief_wait_done(a, 6000);
    scheduler_shutdown();
    scheduler_cleanup();

    ASSERT_TRUE(done);
    ASSERT_EQ(44, atomic_load(&a->result));   // C 42, B 43, A 44
    ASSERT_TRUE(atomic_load(&a->took_ms) < 1000);
    free(a);
    free(b);
    free(c);
}

/* An actor of a core waiting in an ask runs meanwhile: D, on A's core, is
 * sent 20 messages (they fit its mailbox, #3241) while A waits 400 ms for
 * B. They waited for A's reply. */
static void test_ask_relief_other_actor_runs(void) {
    scheduler_init(3);
    ReliefActor* b = relief_actor(1);
    ReliefActor* d = relief_actor(0);
    ReliefActor* a = relief_actor(0);
    b->pause_ms = 400;
    a->ask = (ActorBase*)b;
    a->watch = (ActorBase*)d;
    scheduler_start();

    relief_send(a);
    relief_sleep_ms(50);
    for (int i = 0; i < 20; i++) relief_send(d);
    int done = relief_wait_done(a, 6000);
    scheduler_shutdown();
    scheduler_cleanup();

    ASSERT_TRUE(done);
    ASSERT_EQ(43, atomic_load(&a->result));
    ASSERT_EQ(20, atomic_load(&a->watched));
    ASSERT_EQ(20, atomic_load(&d->got));
    free(a);
    free(b);
    free(d);
}

/* An ask to an actor of the same core whose message is still in the batch
 * the core was delivering: P and T get one message each in one batch while B
 * holds core 0, and P's handler asks T. The ask's message waited behind T's
 * batched one, which nothing placed, to the timeout. */
static void test_ask_relief_target_held_in_batch(void) {
    scheduler_init(2);
    ReliefActor* b = relief_actor(0);
    ReliefActor* p = relief_actor(0);
    ReliefActor* t = relief_actor(0);
    b->pause_ms = 150;
    p->ask = (ActorBase*)t;
    scheduler_start();

    relief_send(b);          // core 0 is busy for 150 ms
    relief_sleep_ms(30);
    relief_send(p);
    relief_send(t);          // behind P's, in the same batch
    int done = relief_wait_done(p, 6000);
    scheduler_shutdown();
    scheduler_cleanup();

    ASSERT_TRUE(done);
    ASSERT_EQ(43, atomic_load(&p->result));
    ASSERT_TRUE(atomic_load(&p->took_ms) < 1000);
    ASSERT_EQ(2, atomic_load(&t->got));
    free(b);
    free(p);
    free(t);
}

void register_ask_relief_tests(void) {
    register_test_with_category("Ask relief: a same-core target held in the batch",
        test_ask_relief_target_held_in_batch, TEST_CATEGORY_RUNTIME);
    register_test_with_category("Ask relief: a chain back to the waiting core",
        test_ask_relief_chain_back_to_waiting_core, TEST_CATEGORY_RUNTIME);
    register_test_with_category("Ask relief: the waiting core's other actors run",
        test_ask_relief_other_actor_runs, TEST_CATEGORY_RUNTIME);
}
