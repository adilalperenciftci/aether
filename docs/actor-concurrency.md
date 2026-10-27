# Aether Runtime Guide

Understanding the actor runtime, concurrency model, and message passing system.

## Performance Optimizations

The actor runtime includes several performance optimizations applied automatically. See [runtime-optimizations.md](runtime-optimizations.md) for detailed descriptions of each technique.

### Scheduler Design

**Partitioned Multicore Scheduler:**
- Locality-aware actor placement at spawn time (actors placed on the caller's core)
- Each core processes only its local actors in the fast path
- Work stealing activated when cores become idle
- Non-blocking work stealing using try-lock with ascending core-id lock ordering
- NUMA-aware allocation when available (Linux and Windows; on macOS `aether_numa_alloc` is a plain `malloc`)
- Message-driven actor migration co-locates communicating actors on the sender's core: an actor a message from another core reaches moves to that core before it runs it, so a chain of sends (a ring, a pipeline) gathers on one core in its first round, where its sends are local
- An actor moves only by its own core, and only while no message for it is on its way through a core's queues (each such message is counted in the actor's `inflight`), so the messages one actor sends another arrive in order across a move (#3090, #3093)

**Work Stealing:**
- Triggered after extended idle scheduler cycles
- Selects the core with the most pending work
- Takes entire actors (not individual messages) to preserve cache locality: the idle core asks the busy one for an actor, and the busy core moves it, as every move is made
- Uses ascending core-id lock ordering consistent with migration to prevent deadlock

**Message Delivery:**
- Same-core messages: direct mailbox or SPSC queue write (no queue overhead)
- Cross-core messages: lock-free queue with batch dequeue
- Adaptive batch processing: 64 to 1024 messages per scheduler cycle

### Active Optimizations

**Sends are asynchronous, whatever the actor count:** the sender goes on and
a scheduler thread runs the handler, from the first actor on (#3112).

**Message Coalescing:**
- Batch dequeue drains multiple messages in a single atomic operation
- Configurable threshold (SCHEDULER_DRAIN_BATCH = 512)

**Thread-Local Message Pools:**
- Per-thread pool of 256 pre-allocated buffers (up to 256 bytes each)
- Eliminates malloc/free on the message hot path
- Falls back to malloc for oversized messages or pool exhaustion

**Direct Send:**
- Bypasses incoming queue for same-core actors
- Writes directly to actor mailbox or SPSC queue
- Guarded by `current_core_id` to prevent data races from non-scheduler threads

**Adaptive Batching:**
- Dynamically adjusts batch size based on queue depth
- Increases under sustained load, decreases when idle

**Inline Single-Int Messages:**
- Messages with one integer field bypass pool allocation entirely
- Value encoded directly in `Message.payload_int`

## Actor Model

Aether implements a lightweight actor model where actors are state machines that communicate via asynchronous messages.

### Actor Lifecycle

1. **Spawn** - Create actor instance with `spawn(ActorName())`
2. **Send** - Send messages with the `!` operator or generated send functions
3. **Step** - Scheduler calls the actor's step function to process mailbox messages
4. **Deactivate** - Actor is marked inactive when its mailbox is empty

### Actor Structure

Each actor is a C struct whose first fields are `ActorBase`'s, since the
scheduler casts a pointer to it to `ActorBase*`. The fields are declared once,
in the `AETHER_ACTOR_BASE_FIELDS` macro (`runtime/scheduler/multicore_scheduler.h`),
and an actor struct expands it first, so its layout cannot drift from the base:

```c
typedef struct {
    AETHER_ACTOR_BASE_FIELDS
    int count;                       // the actor's own state follows
} CounterActor;
```

The fields, in order: `active`, `id`, `mailbox`, `step`, `thread`, `auto_process`, `assigned_core`, `migrate_to`, `spsc_queue`, `reply_slot`, `step_lock`, `timeout_ns`, `last_activity_ns`, `step_payload`, `step_type`, `dead`, `alloc_size`, `destroy_state`, `release_message`, `scheduler_owned`, `inbox`, `thread_parked`, `inflight`. The header comments each one.

An actor the compiler generates holds the base as its first member instead, `ActorBase _aether_base;`, followed by its states. So a state can be named like any of these fields (`state id`, `state active`); only a state named `_aether_base` is refused (#3094).

## Message Passing

### Mailbox

Each actor has a ring buffer mailbox with 32 slots (power-of-2 for fast masking):

```c
#define MAILBOX_SIZE 32
#define MAILBOX_MASK (MAILBOX_SIZE - 1)

typedef struct {
    Message messages[MAILBOX_SIZE];
    int head;
    int tail;
    _Atomic int count;
} Mailbox;
```

The mailbox is a single-producer single-consumer (SPSC) queue. The owning scheduler thread delivers messages and calls the actor's step function. `count` is `_Atomic` to handle the rare case where work-stealing transfers an actor between cores mid-flight. Cross-core messages arrive via the scheduler's per-sender lock-free incoming queues and are delivered to the mailbox by the owning core.

### Message Structure

```c
typedef struct {
    int type;           // Message type ID
    int sender_id;      // Sender actor ID
    intptr_t payload_int; // Integer payload (intptr_t to avoid truncation of actor refs on 64-bit)
    void* payload_ptr;  // Pointer to message data (pool or malloc allocated)
    struct {
        void* data;
        int size;
        int owned;
    } zerocopy;
    void* _reply_slot;  // ActorReplySlot* for ask messages, NULL for fire-and-forget
} Message;
```

### Sending Messages

Messages are sent asynchronously. The generated code routes messages through the scheduler:

```c
// Same-core: direct delivery
if (current_core_id >= 0 && current_core_id == atomic_load_explicit(&actor->assigned_core, memory_order_relaxed)) {
    scheduler_send_local(actor, msg);
} else {
    scheduler_send_remote(actor, msg, current_core_id);
}
```

For single-int messages, the code generator emits an inline path that stores the value directly in `msg.payload_int`, bypassing pool allocation.

A `ptr` field (a `std.bytes` handle, a `*T`) crosses as the pointer, with no copy. To hand the buffer over rather than share it, send it with `move`: `r ! Chunk { data: move buf }`. The sender's `buf` is then moved-from, and any later use of it is a compile error naming the line of the move. See [`move`](isolated.md#move-handing-a-buffer-over-2975).

### Receiving Messages

The `receive` block in the actor definition becomes the step function. The code generator emits a computed goto dispatch table for message handler selection:

```c
void _aether_step_ActorName(ActorName* self) {
    Message msg;
    if (!mailbox_receive(&self->base.mailbox, &msg)) {
        self->base.active = 0;
        return;
    }
    void* _msg_data = msg.payload_ptr;
    int _msg_id = msg.type;

    static void* dispatch_table[256] = {
        [1] = &&handle_MessageA,
        [2] = &&handle_MessageB,
    };

    if (_msg_id >= 0 && _msg_id < 256 && dispatch_table[_msg_id]) {
        goto *dispatch_table[_msg_id];
    }
    aether_message_drop(&self->_aether_base, &msg);   // no handler for it
    return;

    handle_MessageA:
        self->_aether_base.step_payload = _msg_data;
        self->_aether_base.step_type = _msg_id;
        ActorName_handle_MessageA(self, _msg_data);
        self->_aether_base.step_payload = NULL;
        _aether_msg_release_MessageA(_msg_data);   // what its fields own
        aether_free_message(_msg_data);
        return;
}
```

### A message that is not handled

A handled message's fields are released by the step after its handler: `_aether_msg_release_<Msg>` drops what they own (a string the send copied, a closure, a struct that owns), then the payload is freed. A message that is dropped instead is released the same way (#3142). Each program emits one `_aether_release_message(type, payload)`, a switch over its messages that own something, and every spawn stores it in the actor's `release_message`; `aether_message_drop()` calls it and frees the payload. Every drop goes through that function:

- the messages queued to an actor that panicked, or that was released, and the ones sent to it after;
- a message of a type its receiver has no handler for (its payload was not even freed before);
- the message a handler panicked on: the step records it in `step_payload` while the handler runs, and the step's panic barrier drops it, since the release after the handler never ran;
- a message refused because the scheduler is not running, or that could not be queued for lack of memory.

The receiver's own definitions interpret the payload, as its dispatch does, so a message is released as the program that defined it lays it out. A `ptr` field owns nothing (R4), so a buffer sent with `move` and dropped undelivered is not freed: that needs a type that owns a `ptr`, which #3142 tracks. A message sent through a C `AetherActorRef` whose actor was released has only its payload freed, since the block may hold another actor by then, whose definitions need not be the sender's.

### Asking

An ask (`actor ? Msg {}`) sends its message with a reply slot (`Message._reply_slot`) and blocks on the slot until the handler's `reply` fills it or the timeout passes. When no reply can come, the slot says why and the asker returns at once, not at the timeout (#3151):

- an ask to an actor that is already dead (panicked or released) is not sent;
- an ask whose message is dropped undelivered (its target died or was released on the way, or the mailbox it waited in was drained at the death) fails as dead;
- an ask whose handler panics with it in hand fails from the step's panic barrier as "died before it replied";
- an ask whose handler returns without replying fails when its step ends, as "returned without replying".

The ask a handler holds is part of its thread's step context, with the actor stepping. A step can run inside another (a send steps an idle actor of the same core inline, and a cooperative ask polls until its reply), so each step starts with no ask of its own and gives the enclosing step its context back when it ends: a handler that sends, or asks, before it replies still answers its own asker.

`v, err = actor ? Msg {}` reads the reason (the language reference's Ask Pattern lists them); `v = actor ? Msg {}` gives the reply type's zero value for any of them, as it does at a timeout.

An ask made in a handler blocks its core's scheduler thread. Only a core's own scheduler thread does what follows; an actor with a thread of its own sends as a foreign thread and waits without stepping anything for the core (#3246). The core is marked as asking, with the actor it waits on (`Scheduler.ask_target`) and the reply slot (`ask_slot`), and no actor is moved onto it but that one. The waiting thread steps its target itself when the target is the core's (#3220), and relieves the core (#3197): once the wait has lasted `ASK_RELIEF_NS` (1 ms), it does the part of its loop that steps nothing.

- Its deferred sends go out, its own core's through its own queue. A flush already under way on the thread is left to finish (#3247).
- The messages the loop's current batch still holds (`coalesce_buffer.next` marks how far the batch got) go into their actors' mailboxes, for every actor that is not stepping. They are the oldest each has, and the loop skips the entries taken. An actor keeps its entries from the first one that cannot go, so none of its messages passes another. The wait does this at once when its own target is held there.
- Its queued messages go where the loop would put them: into its actors' mailboxes, to an actor's own thread, or on to the core an actor has moved to. A sender's queue is taken in order up to the first message that cannot go now, which the loop delivers once it runs again. That message cannot go when its actor's mailbox is full, or when the batch still holds a message for it.
- Its actors with work (a message, or a receive timeout that is due) and nothing in flight are moved by `move_actor`, the one move path, to a core that runs them. That is the core waiting on that very actor, whose waiting thread is woken through its slot and steps it. When no core waits on it, it goes to a parked core, or else to the core with the fewest messages queued for it that is not asking.

A relief that did something is followed by the next 50 µs later (`ASK_RELIEF_BUSY_NS`). One that found nothing is followed by the next after twice the last gap, up to 8 ms (`ASK_RELIEF_IDLE_MAX_NS`). An actor stepping on this thread (the asker, and any actor below it on the stack) holds its step lock and stays. Nothing is stepped inside the waiting handler: an actor run there that asked the asker could never be answered. Moved to another core, it runs on that core's thread, and an ask of the asker waits there until the asker's handler is done.

An actor with more messages queued than its mailbox holds (32) moves too (#3241). Left in a queue, one of its messages would hold it on the waiting core, and moved without it, its senders' next messages would leave through other queues and could overtake it. So a message the relief finds for an actor whose mailbox is full goes, in order, into an overflow that belongs to the actor: its `inbox`, the unbounded FIFO an actor with a thread of its own takes every message in (#2598), made the first time. There, as in the mailbox, the message is the actor's and no longer counted in flight, and the actor moves with mailbox and overflow together. From then on the overflow holds the actor's newest messages:

- every delivery to it while its overflow holds anything goes behind it: the loop's batch, a local send, a relief, the deferred-send flush, the send buffer;
- every step refills the mailbox from it once the mailbox is down to half, so the mailbox never runs empty while the overflow holds anything, and the loops that step an actor while its mailbox has messages drain both;
- a panic drops what it holds with the mailbox, credited as handled, and a release or a teardown drops and frees it.

Like the mailbox, the overflow is touched only by the thread that runs the actor, and a move hands both over at once. Only a relief starts one: a mailbox found full anywhere else is made room in or queued, as before. The cost on paths that never overflow is one load of `inbox` per delivery and per step.

`tests/runtime/test_ask_relief.c` places the actors on chosen cores. It covers a chain of asks back to the waiting core, the waiting core's other actors, and a same-core target whose message the batch still held; and an actor sent 100 and more messages while its core waits, which moves to another core and handles them all in order, with what is sent to it later, by a local send or through the new core's queue, behind its overflow, and with a panic dropping what the overflow holds.

An ask that was answered or failed returns only once its reply slot is freed. The replier lets go of the slot a few instructions after it wakes the asker, so the asker waits for that and frees the slot itself (#3245). What an ask allocated is gone when it returns, which a program that counts its heap around asks relies on. A timed-out ask does not wait; its replier frees the slot when it comes.

## Actor Timeouts

The `after` clause on a `receive` block fires a handler if no message arrives within a given number of milliseconds:

```aether,fragment
actor Monitor {
    receive {
        Heartbeat -> { println("alive") }
    } after 5000 -> {
        println("no heartbeat for 5s")
    }
}
```

The countdown starts when the actor waits on an empty mailbox: at spawn, and again each time it has handled a message. A message that arrives within the interval stops it, and the next wait starts it from the beginning, as Erlang's `receive ... after` does: the Monitor warns every time 5 seconds pass without a heartbeat. The timeout fires once per countdown. When its handler has run, only a message starts the next one, so a handler that sends the actor a message (`self ! Tick {}` below) keeps a cycle going, and one that sends nothing leaves the actor idle (#3162).

Internally, `timeout_ns` in the actor's base holds the interval, set at spawn and kept, and `last_activity_ns` when the countdown was armed (0 while it is not). The generated `spawn_<Actor>` arms it. The generated step function arms it again at the end of each message's handling, disarms it when it takes a message, and before each `mailbox_receive()` fires the `after` arm (disarming it first) when it is armed, the interval has passed by `_aether_clock_ns()`, and no message is waiting. With no message to step it for, the actor's core (or its own thread) steps it once the deadline passes, so the timeout fires within a park's timed wait of it (32 ms at most). `wait_for_idle()` waits for every armed countdown of a live actor to end (#3102), so a poller that never stops keeps it waiting. The end of `main` waits for the messages sent to be handled, but not for countdowns (#3219): an actor with `after 60000` that handled a message moments before `main` returned does not hold the exit, and its timeout does not run, on either scheduler. `scheduler_shutdown()` calls the wait with countdowns left out, where `wait_for_idle()` keeps them. A program that wants a countdown to fire before it ends calls `wait_for_idle()` first.

The timeout expression can reference actor state fields, not just integer literals, useful when the interval is configurable per-actor or computed:

```aether,fragment
actor Poller {
    state interval_ms = 30000
    state ticks       = 0

    receive {
        Tick -> { ticks = ticks + 1 }
    } after interval_ms -> {
        self ! Tick {}
    }
}
```

Identifiers in the timeout **expression** resolve against actor state fields only. `self` is **not** in scope there: the timeout expression is generated at spawn time (in `spawn_<Actor>`, before `self` exists), so a state-field reference such as `after interval_ms` resolves against the freshly-allocated actor handle. The timeout **body** (above) runs later inside the step function, where `self` *is* in scope, `self ! Tick {}` is fine.

## Panic and Stack Traces

`panic("reason")` unwinds via `aether_panic`. If a `try { ... } catch e { ... }` block (or the scheduler's per-step barrier for actor handlers) is on the stack, the panic is caught and `e` binds to the reason. A reason built at run time (`panic("bad value ${n}")`, a concatenation, a string local) belongs to the catcher: the handler's scope releases it when the handler ends, and whatever keeps it (`kept = e`, a return, a store, a second `panic`) takes a reference of its own, so catching in a loop does not accumulate messages. An actor killed by such a panic releases the reason after its death hook runs. If no frame catches, the runtime prints the reason to stderr along with a filtered stack trace, then aborts:

```text
aether: panic outside any try/catch or actor: divide by zero

Stack trace (most recent call first):
  0: math.safe_divide
  1: calculate_value
  2: main
```

The trace is captured at the call site (codegen wires `aether_panic_capture_stack` in front of every `panic` it lowers) so the user's caller frames survive `-O2` tail-call optimisation. Symbols starting with `aether_` are pretty-printed back to their dotted Aether names, `aether_std_string_concat` reads as `std.string.concat`. User-code symbols pass through verbatim.

The trace is **best-effort diagnostic info**. Under `-O2`, function inlining can fuse callers into one frame; a panic deep inside a chain of small helpers may show only `main`. For richer development-time traces, build with `ae build --quick`, which compiles at `-O0 -g` instead of the default `-O2`; the per-call frames return.

To suppress the trace block entirely (useful for tests that diff stderr line-for-line), set `AETHER_STACK_TRACE=0` in the environment. The reason line still prints.

Available on glibc-Linux and macOS today (uses `<execinfo.h>` `backtrace()` from libc proper, no extra link dependency). On musl, Windows, Emscripten, and freestanding targets the trace block is skipped, `panic`/`try`/`catch` themselves still work.

### Heap cleanup on unwind

A caught panic releases what the scopes it leaves hold, as their exits
would have. While a panic frame is live (a `try`/`catch` block, or the
scheduler's per-step barrier for an actor handler), every place that owns
a value (a string local or temporary, a struct local, an argument the call
must release) is recorded in an unwind journal by its address where it is
declared or first set, and so is every plain `defer` of those scopes.
`aether_panic()` drains the innermost frame's entries before it jumps,
newest first: each place releases what it holds at that moment and is left
empty, and each `defer` runs. `defer try` and `defer catch` do not run on a
panic.

- Stores, moves and releases never touch the journal: the place is recorded
  once, and the drain releases whatever it holds when the panic comes, so a
  value moved elsewhere (returned, stored in a container, actor state or a
  message) is released by its new holder, never by the drain.
- A scope that ends normally forgets its places and runs its `defer`s in
  place.
- A nested `try` drains only the inner frame's entries; the outer frame's
  places are released at their normal exits.
- A place declared outside a `try` and stored inside it is journaled for
  the frame it is declared in (#2690), so a panic the `try` catches leaves
  it to the scope that declared it.

For actor handlers this means a panicking actor's step-scoped values are
released before the actor is marked dead. Outside any frame the journal
calls are a thread-local load and a return, and the no-panic hot path
shows no measurable cost on the ping-pong messaging benchmark. Regression
coverage: `tests/regression/test_panic_unwind_cleanup.ae` (the full
matrix), `tests/integration/panic_unwind_no_leak/` (50000 caught panics,
RSS flat), `tests/integration/panic_actor_step_drain/` (scheduler barrier).

## Cooperative Preemption

By default, message handlers run to completion. A tight compute loop inside a handler will block that core's scheduler thread. For programs where this is a concern, cooperative preemption can be enabled:

- **Scheduler-side**: `AETHER_PREEMPT=1` enables time-based drain loop breaks. After each `actor->step()` call, the scheduler checks elapsed time and yields if the threshold (default 1ms, configurable via `AETHER_PREEMPT_MS`) is exceeded. Cost when disabled: zero.
- **Codegen-side**: `aetherc --preempt` inserts `sched_yield()` calls at loop back-edges in generated C code. A reduction counter (10000 iterations) triggers the yield. Cost when not compiled with `--preempt`: zero (code not generated).

Both levels are independent and can be used alone or together.

## Single-Core Runtime

In single-core mode, actors run cooperatively. The scheduler processes actors in a loop, calling each actor's step function when its mailbox contains messages.

## Multi-Core Runtime

The multi-core scheduler uses core partitioning with locality-aware placement:

- N cores = N independent scheduler threads
- Each scheduler runs in a thread kept on its core: bound to it on Linux, a hint on macOS and Windows
- Actors placed on the caller's core at spawn time (main thread defaults to core 0; scheduler threads use their own core). This keeps parent-child actor groups co-located for efficient local messaging.
- Cross-core messages use lock-free queues with batch dequeue/enqueue
- Message-driven migration converges communicating actors onto the same core

### Synchronization

The `wait_for_idle()` function blocks until all actors have finished processing their messages (quiescence). It is **non-destructive**: it does not stop or join scheduler threads, so it can be called multiple times in a program. This is the recommended way to synchronize the main thread with actor completion:

```aether,fragment
main() {
    ping = spawn(PingActor())
    pong = spawn(PongActor())

    // Send initial message
    ping ! Start {}

    // Wait for all messages to be processed
    wait_for_idle()

    // Actors are now idle, safe to read state
    print(ping.result)

    // Can send more messages and wait again
    ping ! Start {}
    wait_for_idle()
}
```

The implementation uses per-core message counters to detect idle state with minimal overhead on the message-passing hot path. Each scheduler core tracks messages sent and processed locally. The `wait_for_idle()` builtin lowers to the C function `scheduler_wait()`, which sums across cores to determine when all in-flight messages have been handled.

### Initialization

```c
int main() {
    scheduler_init(4);  // Use 4 cores
    scheduler_start();

    // Create and use actors

    scheduler_shutdown();  // Waits for quiescence, stops threads, joins them
}
```

**Scheduler lifecycle functions:**
- `scheduler_wait()`: waits for quiescence (all pending messages processed). Non-destructive: scheduler threads keep running. Safe to call multiple times.
- `scheduler_shutdown()`: waits for quiescence, then stops scheduler threads and joins them. Called once at program exit.
- **Senders the scheduler does not own** (a `std.worker` job, an http pool worker, a C host's thread) must be stopped before `scheduler_shutdown()`: its quiescence wait does not end while one keeps sending. A send from such a thread while the scheduler is not running (shut down, starting again, cleaned up) is refused before it touches a core: the message is dropped, its payload released, the drop counted by `scheduler_stopped_sends()` and reported once on stderr (#2912).

### Core Assignment and Migration

Actors are placed on the caller's core at spawn time. Actors spawned from the main thread default to core 0, keeping top-level actor groups co-located. Actors spawned from within actor handlers inherit the parent's core.

During operation, a sender on another core sets a `migrate_to` hint on the target actor, asking for it on the sender's core. The actor's own core moves it, before it runs the message that brought the request, so a chain of sends (a thread ring, a pipeline) gathers on one core in its first round and its sends turn local. A busy actor whose messages run first is asked again after that batch. A move is non-blocking: if a lock cannot be taken, it waits for the next iteration.

An actor moves only while no message for it is on its way through a core's queues. A sender counts its message in the actor's `inflight` before it reads the actor's core, and the core that delivers the message to the mailbox (or to the actor's own overflow behind it, #3241, which moves with the actor as the mailbox does) uncounts it, a whole run of one actor's messages at once. The move turns `inflight` from 0 to a moving mark, so a message cannot be left behind on the core the actor leaves and then overtaken by the sender's next one (#3093). The same holds for what the moving actor sent itself. A core takes in its messages through one queue per sending core and drains them in index order, so a sender that moved with a message still in a receiver's queue from its old core could have its next one, sent from the new core, delivered first. So a core moves an actor only while nothing sent from that core is still on its way: no core's queue from it holds a message and its overflow is empty (#3240). A message that finds the mailbox full keeps its place: the actor's core steps it to make room, instead of putting the message at the back of a queue. Work stealing goes through the same path: the idle core asks for an actor, and the busy core moves it.

Measured on Windows (i7-13700K, 1,000,000 messages, 10 runs, M msg/s, medians) against the runtime before (#3090): thread ring 24.91 from 3.03, on 0.078 s of CPU from 5.56 s, its 100 actors on one core; fork-join 39.69 from 30.23, each worker's batch delivered as one run; ping-pong (12.56 and 12.36) and counting (42.90 and 42.84) unchanged; skynet 1.69 from 1.31, with a narrower spread.

### Message Routing

- **Same-core messages:** Direct mailbox or SPSC queue write (verified via `current_core_id`), behind any message of the actor still in the queues
- **Cross-core messages:** Counted in the target's `inflight`, then enqueued to the target core's lock-free incoming queue
- **A message on a core the actor has left:** Only one routed by a stale read or by the runtime itself, since a counted message holds the actor where it was routed; forwarded to the actor's current core, still counted

## Memory Management

Actor memory is allocated using NUMA-aware allocation (`aether_numa_alloc_aligned`, on a 64-byte boundary) at spawn time. The `scheduler_spawn_actor` function accepts the full derived-struct size to ensure correct allocation for user-defined actor types.

Message payloads are managed by thread-local pools. Payloads are returned to the pool on free via `aether_free_message`, which checks whether the pointer falls within the pool range before falling back to `free`.

## Memory Model

The actor runtime uses several allocation strategies for automatic cleanup:
- **Actor memory**: one NUMA-aware, 64-byte-aligned allocation per actor at spawn time (`aether_numa_alloc_aligned`), or the kept block of a released actor of the same size. `scheduler_release_actor` takes the actor out of its core's table and retires it; it is reclaimed once every core's scheduler thread and every per-actor thread has passed the top of its loop since, and no other thread is walking the tables. The scheduler threads, per-actor threads and `wait_for_idle`'s scan for armed timeouts read the tables without a lock, so the reclaim has to wait for them; a core blocked in a long step delays it. A reclaimed block is not returned to the allocator while the scheduler runs: it stays marked released, so a send to it is dropped rather than reading freed memory, and the next spawn of that size takes it. The blocks go back with the scheduler's tables. The mailbox is an inline struct member, not a separate allocation.
- **Message payloads**: thread-local pools with automatic return
- **Arenas**: a general-purpose arena allocator provides bulk deallocation without per-object tracking for opt-in uses (`std.arena`, JSON parsing). The actor path does not use arenas.

See [Memory Management](memory-management.md) for details on arenas, pools, and allocation strategies.

## Patterns

- **Per-process configuration**: a module-level `var` holds a scalar set once at startup, but it is module-private and not atomic. State shared across actors uses the actor-singleton pattern: spawn one config actor at startup, drive writes via `Set*` messages, drive reads via `Get*` messages that carry an `actor_ref` reply target. See [per-process-config.md](per-process-config.md) for the worked example, the trade-offs (when message round-trip is acceptable vs. when to plumb the value as a parameter or worker-actor cache), and a port of a real C global-state shim.
