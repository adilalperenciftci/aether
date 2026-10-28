# std.supervise

Supervisors that restart actors (#2974). A supervisor starts its children
from factories, links them, and restarts a child that dies in place, under
the ref its siblings and clients already hold: the factory runs again, and its
spawn of the child's actor type takes the child's own block
(`actors.rebirth_begin`, docs/actor-concurrency.md, "Restart in place").

```aether,run
import std.actors
import std.supervise

message Work {}
message Count {}

actor Worker {
    state done = 0
    receive {
        Work() -> {
            done = done + 1
            if done == 2 { panic("out of paper") }
        }
        Count() -> { reply done }
    }
}

main() {
    sup = supervise.start(strategy: "one_for_one", max_restarts: 3, within_secs: 60) {
        supervise.child("worker", || -> spawn(Worker()))
    }
    w = supervise.which(sup, "worker")
    w ! Work {}
    w ! Work {}   // panics: the worker restarts
    wait_for_idle()
    w ! Work {}   // the same ref reaches the new incarnation
    wait_for_idle()
    int n = w ? Count {}
    println("restarts ${supervise.restarts(sup)}, incarnation ${actors.incarnation(w)}, done ${n}")
}
```
```output
restarts 1, incarnation 1, done 1
```

## Strategies

| `strategy` | A child dies: restarted |
|---|---|
| `"one_for_one"` | that child alone |
| `"one_for_all"` | every child: the others are killed, newest first, and all restart in start order once each one's `Down` has come |
| `"rest_for_one"` | that child and every child started after it |

A death while a restart is still waiting for a `Down` (a sibling killed for
it has not ended yet) joins that restart: each child is restarted once, the
children of both deaths together in start order.

A child's restart kind is `"permanent"` (`supervise.child`, restarted after
any end), `"transient"` (restarted unless it ended `"normal"`) or
`"temporary"` (never), the last two through
`supervise.child_restart(name, factory, kind)`.

## The budget

More than `max_restarts` restarts within `within_secs` seconds (defaults 3
and 5), or a factory that spawns nothing or panics at a restart, and the
supervisor gives up: it kills its children, newest first, and panics with the
reason (`"supervisor gave up: more than 3 restarts within 60 s (worker: out
of paper)"`). So an actor that monitors it gets a `Down` with that reason,
and a supervisor it is linked to (a supervisor of supervisors) takes the
failure in turn.

## Factories

A factory is a closure that spawns the child: `|| -> spawn(Worker())`, or a
block that spawns it and configures it (`|| { w = spawn(Worker()); w ! Config {} }`);
the first actor it spawns is the child. `supervise.start` runs each factory,
in order, before it returns, so `supervise.which(sup, name)` has every child's
ref at once; a factory that spawns nothing there panics the caller. At a
restart the factory runs again on the supervisor, and its spawn takes the
dead child's block: messages queued at the death and sends while it is dead
are dropped and counted (`actors.dead_sends()`), and sends after the restart
reach the new incarnation.

A supervisor holds up to `MAX_CHILDREN` (31) children.

## Exports

`start`, `child`, `child_restart`, `which`, `restarts`, `stop`,
`SuperviseChild`, `SuperviseSpec`, `MAX_CHILDREN`.
