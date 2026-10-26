- **An ask made inside a handler gets its reply in time.** A handler that
  asked an actor it had spawned waited for the reply until its own asker's
  ask had timed out: the ask blocks the core's thread, the asked actor
  started on that core, and since #3090 neither a steal nor gathering could
  move it off a core that waits. The waiting thread steps such a target
  itself, and an ask no longer gathers its target onto the core it blocks
  (#3196, #3220). An actor on another core that asks one of the waiting
  core's other actors in turn still waits: #3197.
