#include "aether_send_buffer.h"
#include "../scheduler/multicore_scheduler.h"
#include <string.h>

// This thread's send buffer: named in this file only (aether_send_buffer.h).
static AETHER_TLS SendBuffer t_send_buffer = {NULL, {{0}}, 0, -1};

SendBuffer* send_buffer_here(void) {
    return &t_send_buffer;
}

// Flush accumulated messages to target actor. Every message goes, always
// (#3292), by the scheduler's own send path: scheduler_send_many sends them
// as that many single sends would go (counted as sent, behind whatever is
// queued for the actor, kept when a queue is full) and enqueues a batch for
// an actor of another core in one step. The flush used to keep what its
// same-core path could not place in the buffer, which then grew past its end;
// to drop the part of a cross-core batch the queue had no room for, still
// counted in flight; to count none of them as sent; and, from a thread that
// is no core's, to write the shared channel without its lock.
void send_buffer_flush(void) {
    if (t_send_buffer.count == 0 || !t_send_buffer.target) {
        return;
    }
    // Taken out of the buffer first: a send can step its target inline, and
    // a handler that buffers sends of its own finds the buffer empty.
    ActorBase* actor = (ActorBase*)t_send_buffer.target;
    int n = t_send_buffer.count;
    Message msgs[SEND_BUFFER_SIZE];
    memcpy(msgs, t_send_buffer.buffer, (size_t)n * sizeof(Message));
    t_send_buffer.count = 0;
    scheduler_send_many(actor, msgs, n);
}
