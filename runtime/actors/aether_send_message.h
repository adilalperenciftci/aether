#ifndef AETHER_SEND_MESSAGE_H
#define AETHER_SEND_MESSAGE_H

#include <stddef.h>
#include <stdint.h>

// Send a typed message to an actor
void aether_send_message(void* actor_ptr, void* message_data, size_t message_size);
// The same, inside a batched loop: the message joins the loop's send batch
// (#3117).
void aether_send_message_batch(void* actor_ptr, void* message_data, size_t message_size);

// Free message payload (tries thread-local pool first, then falls back to free())
void aether_free_message(void* msg_data);

// Get message pool statistics (for profiling)
void aether_message_pool_stats(uint64_t* hits, uint64_t* misses, uint64_t* large);

#endif
