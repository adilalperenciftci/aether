/* #2912: a thread the scheduler does not own sends to an actor while the
 * scheduler is shut down, started again, and cleaned up. Each such send
 * must be refused before it touches a core: the cores' locks are destroyed
 * and made again between lifecycles, and after the cleanup there are no
 * cores at all. */

#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "aether_thread.h"
#include "multicore_scheduler.h"
#include "actor_state_machine.h"

static ActorBase* g_actor;
static atomic_int g_stop;
static atomic_int g_sending;   /* 1: send; 0: pause (and acknowledge in g_paused) */
static atomic_int g_paused;
static atomic_long g_sent;

/* One message per call, as a generated step takes them: the scheduler
 * counts a step as one message processed. */
static void host_step(void* self) {
    ActorBase* a = (ActorBase*)self;
    Message m;
    mailbox_receive(&a->mailbox, &m);
}

static void* sender(void* arg) {
    (void)arg;
    while (!atomic_load(&g_stop)) {
        if (!atomic_load(&g_sending)) {
            atomic_store(&g_paused, 1);
            continue;
        }
        atomic_store(&g_paused, 0);
        Message m;
        memset(&m, 0, sizeof(m));
        m.type = 1;
        scheduler_send_remote(g_actor, m, -1);
        atomic_fetch_add(&g_sent, 1);
    }
    return NULL;
}

/* scheduler_shutdown() waits for the scheduler to go idle, which a sender
 * that never stops prevents: a host stops its senders first. */
static void pause_sender(void) {
    atomic_store(&g_sending, 0);
    while (!atomic_load(&g_paused)) {
    }
}

static void resume_sender(void) {
    atomic_store(&g_paused, 0);
    atomic_store(&g_sending, 1);
}

static void start(void) {
    scheduler_init(2);
    scheduler_start();
    scheduler_register_actor(g_actor, -1);
}

int sched_lifecycle_probe(void) {
    /* The caller's own actor, which no teardown frees: 64-byte aligned, as
     * an actor block is. */
    size_t size = (sizeof(ActorBase) + 63) & ~(size_t)63;
    void* raw = malloc(size + 64);
    if (!raw) return 1;
    g_actor = (ActorBase*)(((uintptr_t)raw + 63) & ~(uintptr_t)63);
    memset(g_actor, 0, size);
    mailbox_init(&g_actor->mailbox);
    g_actor->step = host_step;

    start();
    atomic_store(&g_sending, 1);
    pthread_t t;
    if (pthread_create(&t, NULL, sender, NULL) != 0) return 2;
    /* The sender is running through every teardown and start below: the
     * shutdown's end, the next scheduler_init() freeing the previous
     * lifecycle's tables and making new ones, and the cleanup. */
    for (int round = 0; round < 25; round++) {
        usleep(2000);
        pause_sender();
        scheduler_shutdown();
        resume_sender();
        usleep(1000);
        start();
    }
    usleep(2000);
    pause_sender();
    scheduler_shutdown();
    resume_sender();
    scheduler_cleanup();
    usleep(5000);
    atomic_store(&g_stop, 1);
    pthread_join(t, NULL);

    if (atomic_load(&g_sent) == 0) return 3;
    if (scheduler_stopped_sends() == 0) {
        printf("FAIL: no send made while the scheduler was stopped was refused\n");
        return 4;
    }
    printf("sched_foreign_send_lifecycle passed\n");
    free(raw);
    return 0;
}
