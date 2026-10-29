- **An interruption inside an actor's end goes on to its call.** The frame
  that runs an ending actor's message drops (#3401) caught every panic,
  the call's interruption included: when a call ended an actor there and
  then (a kill on the cooperative runtime) and a drop ran a loop past the
  call's deadline, the interruption was reported as the drop's panic and
  left marked, so the call's next ordinary panic, in a later call's `try`,
  was raised again as the interruption. A containment frame (`aether_contain`,
  which the step barrier's drop uses too) now takes the interruption off
  its way and notes it as the call's stop: the call ends with it at its
  next safe point, or when it returns (#3404).
