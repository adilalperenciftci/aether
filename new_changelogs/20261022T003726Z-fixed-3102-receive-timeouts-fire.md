- **A receive timeout fires in a program with more than one actor.**
  `receive { ... } after N -> { ... }` fired only in main-thread mode, a
  program with one actor. On the scheduler's cores nothing stepped an
  actor whose mailbox was empty, so the timeout of an actor that received
  nothing never fired, and `wait_for_idle()` returned without waiting
  for it. Now the actor's core, or its own thread, steps it once the
  deadline passes, within a park's timed wait (32 ms at most). And
  `wait_for_idle()` waits for armed timeouts, as main-thread mode does
  (#3102).
