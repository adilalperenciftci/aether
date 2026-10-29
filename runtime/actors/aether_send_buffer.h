#ifndef AETHER_SEND_BUFFER_H
#define AETHER_SEND_BUFFER_H

#include "actor_state_machine.h"
#include "../utils/aether_thread.h"

// Forward declarations to avoid circular dependencies
struct ActorBase;

/**
 * Sender-Side Message Batching
 *
 * Reduces atomic operations by accumulating messages in thread-local buffers
 * before flushing to mailboxes in batches.
 *
 * Performance impact:
 * - Before: N messages → N atomic operations on the target queue.
 * - After:  N messages → roughly N/256 atomic operations (one per flushed batch).
 * - Batching amortises the cross-core enqueue cost; the win scales with
 *   message density.
 */

#define SEND_BUFFER_SIZE 256

// Thread-local send buffer for batching messages to same target
typedef struct {
    void* target;               // Target actor (ActorBase* or similar)
    Message buffer[SEND_BUFFER_SIZE];
    int count;
    int core_id;                // Core ID for cross-core detection
} SendBuffer;

// The calling thread's buffer. It is a `static` thread-local of
// aether_send_buffer.c, and only that file names it: a thread-local of
// several fields stays in the file that defines it, and every other file
// reaches it through this function (runtime/actors/aether_frames.h says
// why). The functions below write the fields through the pointer it
// returns. They stay inline: a buffered send made a call into that file
// took 5.7 ns, the Message passed by value copied twice, against 1.57 ns
// for an inline store through the pointer (1.55 ns when the buffer was an
// extern thread-local; both with the loop aligned, since the placement of
// the caller's loop moves either by more than that).
SendBuffer* send_buffer_here(void);

// Send what the buffer holds, all of it (#3292).
void send_buffer_flush(void);

// Initialize send buffer for current thread
static inline void send_buffer_init(int core_id) {
    SendBuffer* b = send_buffer_here();
    b->target = NULL;
    b->count = 0;
    b->core_id = core_id;
}

// Buffered send - accumulates messages before flushing. A flush sends every
// message it holds (#3292), but a send in it can step a handler inline that
// buffers sends of its own, for another target: those are flushed too, so
// the message below is stored in a buffer with room, for its own target.
static inline void send_buffered(struct ActorBase* actor, Message msg) {
    SendBuffer* b = send_buffer_here();
    while (b->count > 0 && (b->target != actor || b->count >= SEND_BUFFER_SIZE)) {
        send_buffer_flush();
    }
    b->target = actor;
    b->buffer[b->count++] = msg;
}

// Force flush of pending messages (call before blocking operations)
static inline void send_buffer_force_flush(void) {
    SendBuffer* b = send_buffer_here();
    while (b->count > 0) {
        send_buffer_flush();
    }
    b->target = NULL;
}

// Get buffer stats for monitoring
static inline int send_buffer_pending(void) {
    return send_buffer_here()->count;
}

#endif // AETHER_SEND_BUFFER_H
