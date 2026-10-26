- **An ask made inside a handler gets its reply in time.** A handler that
  asked an actor it had spawned waited for the reply until its own asker's
  ask had timed out: the ask blocks the core's thread, the asked actor
  started on that core, and since #3090 neither a steal nor gathering could
  move it off a core that waits. The asking core moves such a target to its
  least busy other core before it waits, and an ask no longer gathers its
  target onto the core it blocks (#3196). A deeper chain, an actor on the
  waiting core that the asked one asks in turn, still waits: #3197.
