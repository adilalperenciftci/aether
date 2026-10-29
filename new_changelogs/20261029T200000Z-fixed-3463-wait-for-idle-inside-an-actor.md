- **`wait_for_idle()` inside an actor panics instead of never returning.**
  It waits for every actor, the calling one too, whose step cannot end
  while it waits: in a message handler it hung forever (the handler's own
  message stays counted until the step returns), in a receive timeout's arm
  it waited until its bound. Called inside an actor's step, on either
  scheduler, it now panics as the actor's code, and the actor ends with a
  reason that says to call it outside the actors (main, or a host's
  thread); its watchers are told, and the program goes on (#3463).
