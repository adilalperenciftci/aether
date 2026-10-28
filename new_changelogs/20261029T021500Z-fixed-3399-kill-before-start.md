- **An actor ended before `scheduler_start` is finalized at once
  (#3399).** `scheduler_actor_end` took an initialized scheduler for a
  running one and posted the finalize to the actor's core, but
  `scheduler_init` marks the scheduler initialized before
  `scheduler_start` makes the core threads. A C host that killed an actor
  between the two waited for a start to finalize it, and one that never
  started the cores never did: no `Down` went out, an actor linked to it
  lived on, and `scheduler_wait` and `scheduler_shutdown` returned without
  it. The request is posted only once the threads are started; before,
  the death is finalized on the killing thread, as after a stop.
