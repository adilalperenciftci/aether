# std.actors

A process-global registry mapping names to actor references.

Models BEAM's `erlang:register` / `erlang:whereis`. The problem it solves is
reach: an actor spawned at startup needs to be addressable from a callback
that has nowhere to carry an `actor_ref`: a `@c_callback` handler, a
signal-driven path, a plugin entry point. Registering it under a name means
any of those can find it.

```aether,run
import std.actors

message Bump {}

actor Counter {
    state count = 0
    receive { Bump() -> { count = count + 1 } }
}

main() {
    actors.registry_clear()

    counter = spawn(Counter())
    actors.register("counter", counter)

    println("registered: ${actors.is_registered("counter")}")
    println("size:       ${actors.registry_size()}")

    // whereis returns the ref, usable for sending.
    found = actors.whereis("counter")
    found ! Bump {}

    println("unregister: ${actors.unregister("counter")}")
    println("again:      ${actors.unregister("counter")}")
}
```
```output
registered: 1
size:       1
unregister: 1
again:      0
```

Registering a name that is already bound **overwrites** without error:
last writer wins, and the map does not grow. `unregister` returns 1 if it
removed a binding and 0 if the name was not bound, which is the difference
between "I cleaned up" and "someone else already did".

`whereis` on an unbound name returns null, so check before sending.

## Ending actors, and death notices (#2974)

An actor ends once: its handler panics, `actors.kill(ref)` ends it (from
anywhere), or its own handler calls `actors.stop()`. A kill or a stop takes
effect when the running handler returns. What was queued for it is dropped,
and so is every send to it after, each counted by `actors.dead_sends()`.

`actors.monitor(ref)`, from a handler, asks for one `Down { ref, reason }`
when `ref` ends: `"normal"` for a stop, `"killed"` for a kill, the panic's
message for a panic, and at once for an actor that has ended already. The
compiler declares `Down`; an actor handles it in a `Down(ref, reason)` arm.
`actors.demonitor(id)` drops a monitor, and no `Down` of it is handled after.

```aether,run
import std.actors

message Watch { who: actor_ref }
message Halt {}

actor Job {
    receive { Halt() -> { actors.stop() } }
}

actor Boss {
    receive {
        Watch(who) -> { _id = actors.monitor(who) }
        Down(ref, reason) -> { println("job ended: ${reason}") }
    }
}

main() {
    j = spawn(Job())
    b = spawn(Boss())
    b ! Watch { who: j }
    wait_for_idle()
    j ! Halt {}
    wait_for_idle()
}
```
```output
job ended: normal
```

`actors.link(ref)` ties two actors both ways: when either ends, the other
ends too, with the same reason, unless it is `"normal"`; an actor that called
`actors.trap_exits(true)` gets a `Down` instead and lives on.
`actors.unlink(ref)` takes the tie away.

On wasi a panic ends the program, so `monitor`, `link` and `trap_exits` are
refused when compiling for it. See docs/actor-concurrency.md, "The end of an
actor".

## Exports

`register`, `whereis`, `unregister`, `is_registered`, `registry_size`,
`registry_clear`, `monitor`, `demonitor`, `kill`, `stop`, `dead_sends`, `link`,
`unlink`, `trap_exits`.
