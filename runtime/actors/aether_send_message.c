#include "actor_state_machine.h"
#include "../scheduler/multicore_scheduler.h"
#include "../config/aether_optimization_config.h"
#include "../utils/aether_compiler.h"
#include <string.h>
#include <stdlib.h>
#include "../utils/aether_thread.h"
#include "../../std/string/aether_string.h"
#include "../aether_resource_caps.h"
#include "aether_frames.h"
#include "aether_panic.h"

// Thread-local core ID for optimization
extern AETHER_TLS int current_core_id;

// ActorBase is defined in multicore_scheduler.h

// ==============================================================================
// Message payloads
// ==============================================================================
// A typed message's payload is a heap copy (payload_message below), freed by
// whoever handles or drops the message. There is no payload pool (#3374):
// its acquire side was removed because an actor can move to another core
// after a message is sent, so a pooled payload would be released by a
// thread that does not own the pool.

/* Deprecated (#3374): there is no pool, so there is nothing to count; kept
 * for callers built against it, it reports zeros. */
void aether_message_pool_stats(uint64_t* hits, uint64_t* misses, uint64_t* large) {
    if (hits) *hits = 0;
    if (misses) *misses = 0;
    if (large) *large = 0;
}

void aether_free_message(void* msg_data) {
    free(msg_data);
}

void aether_message_drop(ActorBase* target, Message* msg) {
    if (msg->payload_ptr) {
        if (msg->type == AETHER_MSG_DOWN) {
            // The runtime wrote it (#2974): its reason is the runtime's to
            // release, whether or not the program declares Down.
            string_release(((AetherDownMsg*)msg->payload_ptr)->reason);
        } else if (target && target->release_message) {
            target->release_message(msg->type, msg->payload_ptr);
        }
        aether_free_message(msg->payload_ptr);
        msg->payload_ptr = NULL;
    }
    if (msg->zerocopy.owned && msg->zerocopy.data) {
        free(msg->zerocopy.data);
        msg->zerocopy.data = NULL;
        msg->zerocopy.owned = 0;
    }
}

// The heap copy of a typed message's payload, or NULL when there was no
// memory for it.
// Always use heap allocation for type-safe messages.
// TLS pools have thread affinity issues: a same-core actor may be migrated
// to another core after the message is sent, causing the receiver to call
// free() on pool memory (heap-use-after-free / free-on-non-malloc).
static void* payload_copy(void* message_data, size_t message_size) {
    void* msg_copy = aether_alloc_test_refuses() ? NULL : malloc(message_size);
    if (msg_copy) memcpy(msg_copy, message_data, message_size);
    return msg_copy;
}

static Message message_of(void* payload, int type, void* reply_slot) {
    Message msg;
    msg.type = type;
    msg.sender_id = 0;
    msg.payload_int = 0;
    msg.payload_ptr = payload;
    msg.zerocopy.data = NULL;
    msg.zerocopy.size = 0;
    msg.zerocopy.owned = 0;
    msg._reply_slot = reply_slot;
    return msg;
}

// The heap copy of a typed message's payload, as the Message a send carries.
static Message payload_message(ActorBase* actor, void* message_data, size_t message_size) {
    void* msg_copy = payload_copy(message_data, message_size);
    if (!msg_copy) {
        /* Inside a library call (#2956): nothing is queued yet, so the
         * message's own values are released (they moved into it) and the
         * call ends with AETHER_OUT_OF_MEMORY. Elsewhere the process stops,
         * as it always did: the send has no way to fail. */
        if (aether_frames_here()->exec_depth > 0) {
            if (actor->release_message) actor->release_message(*(int*)message_data, message_data);
            aether_out_of_memory("out of memory copying a message");
        }
        fprintf(stderr, "aether: malloc(%zu) failed for msg type %d to actor %d\n",
                message_size, *(int*)message_data, actor->id);
        abort();
    }
    return message_of(msg_copy, *(int*)message_data, NULL);
}

// An ask's message (#3387): the payload copied, the asker's reply slot in it.
// An ask can fail, so a copy that finds no memory is its failure, not an
// unwind: 0, with what the message owns released (its values moved into it)
// and nothing sent. The slot is passed here rather than through a
// thread-local the send reads: the send can step its target inline, and
// every payload send that handler made read the asker's slot too.
int aether_ask_message(void* actor_ptr, void* message_data, size_t message_size,
                       void* reply_slot, Message* out) {
    ActorBase* actor = (ActorBase*)actor_ptr;
    void* msg_copy = payload_copy(message_data, message_size);
    if (!msg_copy) {
        if (actor && actor->release_message) actor->release_message(*(int*)message_data, message_data);
        return 0;
    }
    *out = message_of(msg_copy, *(int*)message_data, reply_slot);
    return 1;
}

// Send a typed message to an actor. The payload is copied to the heap and
// handed to the scheduler, which delivers it whatever the actor count
// (#3112): the handler runs later, on a scheduler thread, and the sender
// goes on. The cooperative runtime queues it for the next wait_for_idle or
// aether_scheduler_poll.
void aether_send_message(void* actor_ptr, void* message_data, size_t message_size) {
    ActorBase* actor = (ActorBase*)actor_ptr;
    aether_send_built(actor, payload_message(actor, message_data, message_size));
}

// A message built already (an ask's), to its actor: through this core when
// the actor is this core's, else through its own.
void aether_send_built(ActorBase* actor, Message msg) {
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

// try_send(ref, Msg {...}) of a payload message (#2974): sent as
// aether_send_message sends it, unless the actor is dead or its mailbox
// full, which it says ("" when sent).
const char* aether_try_send_message(void* actor_ptr, void* message_data, size_t message_size) {
    ActorBase* actor = (ActorBase*)actor_ptr;
    if (!actor) return "the actor is dead";
    return scheduler_try_send(actor, payload_message(actor, message_data, message_size));
}

// A typed message sent inside a batched loop (#3117): it joins the batch, as
// the loop's one-int messages do, so the loop's sends keep their order.
void aether_send_message_batch(void* actor_ptr, void* message_data, size_t message_size) {
    ActorBase* actor = (ActorBase*)actor_ptr;
    scheduler_send_batch_add(actor, payload_message(actor, message_data, message_size));
}
