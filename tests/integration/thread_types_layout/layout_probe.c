/* Prints the layout of the runtime structs a program and libaether share
 * that hold a thread, a mutex or a condition (#3120). Built as a program's
 * C is: on Windows with AETHER_THREAD_TYPES_ONLY, the types alone. */
#include <stddef.h>
#include <stdio.h>
#ifdef _WIN32
#define AETHER_THREAD_TYPES_ONLY 1
#endif
#include "multicore_scheduler.h"

#define SIZE(S) printf("sizeof(" #S ") %lu\n", (unsigned long)sizeof(S))
#define AT(S, f) printf(#S "." #f " %lu\n", (unsigned long)offsetof(S, f))

int main(void) {
    SIZE(ActorBase);
    AT(ActorBase, active);
    AT(ActorBase, id);
    AT(ActorBase, mailbox);
    AT(ActorBase, step);
    AT(ActorBase, thread);
    AT(ActorBase, auto_process);
    AT(ActorBase, assigned_core);
    AT(ActorBase, migrate_to);
    AT(ActorBase, main_thread_only);
    AT(ActorBase, spsc_queue);
    AT(ActorBase, reply_slot);
    AT(ActorBase, step_lock);
    AT(ActorBase, timeout_ns);
    AT(ActorBase, last_activity_ns);
    AT(ActorBase, dead);
    AT(ActorBase, alloc_size);
    AT(ActorBase, destroy_state);
    AT(ActorBase, scheduler_owned);
    AT(ActorBase, inbox);
    AT(ActorBase, thread_parked);
    AT(ActorBase, inflight);
    SIZE(ActorReplySlot);
    AT(ActorReplySlot, mutex);
    AT(ActorReplySlot, cond);
    AT(ActorReplySlot, refcount);
    SIZE(Scheduler);
    AT(Scheduler, thread);
    AT(Scheduler, actor_table);
    AT(Scheduler, foreign_lock);
    AT(Scheduler, running);
    AT(Scheduler, park_mutex);
    AT(Scheduler, park_cond);
    AT(Scheduler, parked);
    AT(Scheduler, io_registered_count);
    return 0;
}
