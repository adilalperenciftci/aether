/* #3401: a panic in the release of a message an ending actor leaves
 * undelivered does not stop the actor's end.
 *
 * An actor's end drops what waits for it, and a dropped message's release
 * is the program's code for a field of an owned type (its drop function,
 * #3142), which may panic. Where a death is finalized as soon as it is seen
 * (the cooperative scheduler, and the threaded one once stopped), the panic
 * left the finalize: the messages after it were not released, and the
 * actor's watchers and links were never told. Here victim `v` holds three
 * messages, the first of which panics in its release; `l` is linked to it
 * and `w` monitors it. Killing `v` must release the other two, end `l`
 * (and, where the Down can be delivered, the cooperative scheduler, give
 * `w` its Down), let no panic out, and report the panic through the death
 * hook as the step barrier reports a panic in a release after a handler.
 *
 * #3417: the same with a death hook that panics when it is told of the
 * release's panic. The hook ran bare there, so its panic left the finalize
 * halfway, after the first message: the rest were never released or
 * counted, and the links and watchers never told. It runs in a frame of its
 * own now, and the end goes on.
 *
 * Built twice by test_finalize_drop_panic.sh: against libaether (the
 * threaded scheduler, stopped before the kill) and against the cooperative
 * runtime. */

#include "multicore_scheduler.h"
#include "aether_panic.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_released = 0;
static int g_hook_calls = 0;
static int g_hook_actor = -1;
static int g_hook_panics = 0;
static char g_hook_reason[64];

/* Message type 9 carries an int: 1 panics in the release, any other is
 * released and counted. */
static void release(int type, void* payload) {
    if (type != 9 || !payload) return;
    if (*(int*)payload == 1) aether_panic("the drop panicked");
    g_released++;
}

static void on_death(int actor_id, const char* reason) {
    g_hook_calls++;
    g_hook_actor = actor_id;
    snprintf(g_hook_reason, sizeof g_hook_reason, "%s", reason ? reason : "");
    if (g_hook_panics) aether_panic("the death hook panicked");
}

static void step(void* self) {
    (void)self;
}

static void queue(ActorBase* a, int value) {
    Message m;
    memset(&m, 0, sizeof m);
    m.type = 9;
    int* p = (int*)malloc(sizeof(int));
    *p = value;
    m.payload_ptr = p;
    mailbox_send(&a->mailbox, m);
}

typedef struct {
    ActorBase* v;   // the victim
    ActorBase* l;   // linked to it
    ActorBase* w;   // monitors it
} EndCase;

static EndCase end_case(void) {
    EndCase c;
    c.v = scheduler_spawn_actor(0, step, sizeof(ActorBase));
    c.l = scheduler_spawn_actor(0, step, sizeof(ActorBase));
    c.w = scheduler_spawn_actor(0, step, sizeof(ActorBase));
    aether_step_actor_set(c.l);   // as from l's handler
    aether_actor_link(c.v);
    aether_step_actor_set(c.w);
    aether_actor_monitor(c.v);
    aether_step_actor_set(NULL);
    return c;
}

/* Kills the case's victim with its three messages queued; the number of
 * checks that failed. */
static int end_check(const char* label, EndCase c, int hook_panics) {
    c.v->release_message = release;
    queue(c.v, 1);
    queue(c.v, 2);
    queue(c.v, 3);
    g_released = 0;
    g_hook_calls = 0;
    g_hook_actor = -1;
    g_hook_reason[0] = '\0';
    g_hook_panics = hook_panics;
    uint64_t dead0 = scheduler_dead_sends();

    int escaped = 0;
    AetherJmpFrame* f = aether_try_push();
    if (AETHER_SIGSETJMP(f->buf, 1) == 0) {
        aether_actor_kill(c.v);
    } else {
        escaped = 1;
    }
    aether_try_pop();

    int fails = 0;
    if (escaped) {
        printf("FAIL (%s): a panic left the actor's end\n", label);
        fails++;
    }
    if (g_released != 2) {
        printf("FAIL (%s): %d of the 2 messages after the panicking one were released\n", label,
               g_released);
        fails++;
    }
    uint64_t dead = scheduler_dead_sends() - dead0;
    if (dead != 3) {
        printf("FAIL (%s): %d of the 3 messages dropped were counted\n", label, (int)dead);
        fails++;
    }
    if (!((atomic_load(&c.l->dead) & AETHER_ACTOR_KILLED) &&
          (atomic_load(&c.l->exit_flags) & AETHER_EXIT_FINALIZED))) {
        printf("FAIL (%s): the linked actor did not take the death\n", label);
        fails++;
    }
#ifdef AETHER_NO_THREADING
    Message got;
    int down = 0;
    while (mailbox_receive(&c.w->mailbox, &got)) {
        if (got.type == AETHER_MSG_DOWN) down++;
        aether_message_drop(c.w, &got);
    }
    if (down != 1) {
        printf("FAIL (%s): the watcher got %d Down, not 1\n", label, down);
        fails++;
    }
#endif
    if (g_hook_calls != 1 || g_hook_actor != c.v->id ||
        strcmp(g_hook_reason, "the drop panicked") != 0) {
        printf("FAIL (%s): the death hook saw %d call(s), actor %d, \"%s\"\n", label, g_hook_calls,
               g_hook_actor, g_hook_reason);
        fails++;
    }
    return fails;
}

int main(void) {
    scheduler_init(1);
    EndCase quiet = end_case();
    EndCase loud = end_case();
#ifndef AETHER_NO_THREADING
    /* Stopped, the threaded scheduler finalizes a death where it is seen,
     * as the cooperative one always does. */
    scheduler_shutdown();
#endif
    aether_set_on_actor_death(on_death);
    int fails = end_check("a drop that panics", quiet, 0);
    fails += end_check("and a death hook that panics too", loud, 1);
    aether_set_on_actor_death(NULL);
    if (fails) return 1;
    printf("PASS\n");
    return 0;
}
