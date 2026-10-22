- **A send is asynchronous whatever the number of actors.** With one actor
  the runtime ran the handler inside the sender's `!` ("main-thread mode")
  until a second actor was spawned, so a handler that blocked on something
  its sender was about to do deadlocked the program, the order of a
  program's output depended on its actor count, and tests and examples
  spawned a do-nothing actor to get the real behaviour. Every send now goes
  through the scheduler from the first actor on, and the cooperative
  (no-threads) runtime queues it for the next `wait_for_idle`,
  `aether_scheduler_poll` or shutdown. `AETHER_INLINE` and
  `AETHER_NO_INLINE` are gone with the mode, and `aether_scheduler_poll`
  returns 0 with threads: there is nothing left for a host to drain. A
  program that printed from a handler and then from `main` and relied on
  that order calls `wait_for_idle()` between them (#3112).
