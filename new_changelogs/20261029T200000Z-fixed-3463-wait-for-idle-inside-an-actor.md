- **`wait_for_idle()` inside an actor panics instead of never returning.**
  It waits for every actor, the calling one too, whose step cannot end
  while it waits: in a message handler it hung forever (the handler's own
  message stays counted until the step returns), in a receive timeout's arm
  it waited until its bound, and in a drop or a death hook a core ran after
  the step, forever. Called inside an actor's step, on either scheduler,
  or on the threaded scheduler on any thread that runs actors, it now
  panics as the actor's code: the actor ends with a reason that says to
  call it outside the actors (main, or a host's thread), its watchers are
  told, and the program goes on. On the cooperative scheduler, where the
  wait ran the other actors nested and returned, it panics too, so a
  program behaves the same on both (#3463).
