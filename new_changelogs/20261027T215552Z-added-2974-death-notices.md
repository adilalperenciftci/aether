- **An actor can be ended, and its death watched.** `import std.actors`:
  `actors.kill(ref)` ends an actor from anywhere and `actors.stop()` ends the
  one whose handler calls it, each once the running handler returns; a panic
  ends it as before. `actors.monitor(ref)` asks for one `Down { ref, reason }`
  when `ref` ends (`"normal"`, `"killed"`, or the panic's message), at once
  for one that has ended already, and `actors.demonitor(id)` drops it, one
  already on its way included. `Down` is declared by the compiler (a
  program's own `message Down` is refused) and handled in a
  `Down(ref, reason)` arm. A death is finalized on the thread that owns the
  actor's mailbox while it steps nothing, so a `Down` never comes while its
  handler still runs and comes after the last messages it sent; what was
  queued for it, and every send to it after, is dropped and counted
  (`actors.dead_sends()`, `scheduler_dead_sends()`); an ask its killed
  handler waits in ends at once with "the asking actor was killed". On wasi,
  where a panic ends the program, `actors.monitor` is refused at compile
  time (#2974).
