#include "actor_state_machine.h"
#include "../scheduler/multicore_scheduler.h"
#include "../config/aether_optimization_config.h"
#include "../utils/aether_compiler.h"
#include <string.h>
#include <stdlib.h>
#include "../utils/aether_thread.h"

// Thread-local core ID for optimization
extern AETHER_TLS int current_core_id;

// ActorBase is defined in multicore_scheduler.h

// ==============================================================================
// TIER 1 OPTIMIZATION: Thread-Local Message Payload Pool
// ==============================================================================
// Instead of malloc/free for every message payload (one alloc + one free per
// send/receive cycle on the hot path), draw from a per-thread pool of small
// buffers. Eliminates the allocator as a bottleneck for small-message traffic.

#define MSG_PAYLOAD_POOL_SIZE 256      // 256 buffers per thread
#define MSG_PAYLOAD_MAX_SIZE 256       // Max pooled message size (Ping/Pong ~16 bytes)

typedef struct {
    char buffer[MSG_PAYLOAD_MAX_SIZE];
    int in_use;  // Thread-local: no atomics needed
} PooledPayload;

typedef struct {
    PooledPayload payloads[MSG_PAYLOAD_POOL_SIZE];
    int next_index;  // Thread-local: no atomics needed
    int initialized;
} PayloadPool;

// Thread-local payload pool
static AETHER_TLS PayloadPool* g_payload_pool = NULL;

// Global statistics (atomic, shared across all threads)
static _Atomic uint64_t g_pool_hits = 0;
static _Atomic uint64_t g_pool_misses = 0;
static _Atomic uint64_t g_too_large = 0;

// Get pool statistics (for debugging/profiling)
void aether_message_pool_stats(uint64_t* hits, uint64_t* misses, uint64_t* large) {
    *hits = atomic_load_explicit(&g_pool_hits, memory_order_relaxed);
    *misses = atomic_load_explicit(&g_pool_misses, memory_order_relaxed);
    *large = atomic_load_explicit(&g_too_large, memory_order_relaxed);
}

// Initialize thread-local payload pool
/* The acquire side of this pool was removed: it was unreachable, and the
 * send path below documents why it must stay that way. An actor can be
 * migrated to another core after a message is sent, so a TLS-pooled
 * payload would be released by a thread that does not own that pool.
 * payload_pool_release still runs and simply reports "not mine" for
 * every heap payload. */


// Return payload to pool
static inline int payload_pool_release(void* ptr) {
    if (!g_payload_pool || !g_payload_pool->initialized) {
        return 0;  // Not from pool
    }

    // Check if pointer is within pool memory
    char* pool_start = (char*)g_payload_pool->payloads;
    char* pool_end = pool_start + sizeof(g_payload_pool->payloads);

    if ((char*)ptr < pool_start || (char*)ptr >= pool_end) {
        return 0;  // Not from pool
    }

    // Find which slot this is
    size_t offset = (char*)ptr - pool_start;
    size_t slot_index = offset / sizeof(PooledPayload);

    if (slot_index >= MSG_PAYLOAD_POOL_SIZE) {
        return 0;  // Invalid
    }

    // Mark as free (thread-local: plain store)
    g_payload_pool->payloads[slot_index].in_use = 0;
    return 1;  // Successfully returned to pool
}

// Free message payload - try pool first, then fall back to free()
void aether_free_message(void* msg_data) {
    if (!msg_data) return;

    // Try to return to pool
    if (payload_pool_release(msg_data)) {
        return;  // Returned to pool successfully
    }

    // Was malloc'd (large message or pool exhausted), use regular free
    free(msg_data);
}

// The heap copy of a typed message's payload, as the Message a send carries.
static Message payload_message(ActorBase* actor, void* message_data, size_t message_size) {
    // Always use heap allocation for type-safe messages.
    // TLS pools have thread affinity issues: a same-core actor may be migrated
    // to another core after the message is sent, causing the receiver to call
    // free() on pool memory (heap-use-after-free / free-on-non-malloc).
    void* msg_copy = malloc(message_size);
    if (!msg_copy) {
        fprintf(stderr, "aether: malloc(%zu) failed for msg type %d to actor %d\n",
                message_size, *(int*)message_data, actor->id);
        abort();
    }
    memcpy(msg_copy, message_data, message_size);

    Message msg;
    msg.type = *(int*)message_data;
    msg.sender_id = 0;
    msg.payload_int = 0;
    msg.payload_ptr = msg_copy;
    msg.zerocopy.data = NULL;
    msg.zerocopy.size = 0;
    msg.zerocopy.owned = 0;
    msg._reply_slot = g_pending_reply_slot;
    return msg;
}

// Send a typed message to an actor. The payload is copied to the heap and
// handed to the scheduler, which delivers it whatever the actor count
// (#3112): the handler runs later, on a scheduler thread, and the sender
// goes on. The cooperative runtime queues it for the next wait_for_idle or
// aether_scheduler_poll.
void aether_send_message(void* actor_ptr, void* message_data, size_t message_size) {
    ActorBase* actor = (ActorBase*)actor_ptr;
    Message msg = payload_message(actor, message_data, message_size);

#if AETHER_HAS_THREADS
    // Cache TLS once — avoids repeated tlv_get_addr calls on macOS
    const int my_core = current_core_id;

    if (my_core >= 0 && my_core == atomic_load_explicit(&actor->assigned_core, memory_order_relaxed)) {
        scheduler_send_local(actor, msg);
    } else {
        scheduler_send_remote(actor, msg, my_core);
    }
#else
    scheduler_send_local(actor, msg);
#endif
}

// A typed message sent inside a batched loop (#3117): it joins the batch, as
// the loop's one-int messages do, so the loop's sends keep their order.
void aether_send_message_batch(void* actor_ptr, void* message_data, size_t message_size) {
    ActorBase* actor = (ActorBase*)actor_ptr;
    scheduler_send_batch_add(actor, payload_message(actor, message_data, message_size));
}
