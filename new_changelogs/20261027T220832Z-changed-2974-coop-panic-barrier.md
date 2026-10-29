- **A panic on the cooperative scheduler ends the actor, not the program.**
  The cooperative scheduler (Emscripten, esp32, `-DAETHER_NO_THREADING`)
  stepped actors with no panic barrier, so a handler's panic ended the
  program. Both schedulers now step inside one barrier
  (`runtime/actors/aether_step_barrier.h`): the actor ends, the message and
  the ask it held are dropped and failed, its death is finalized and its
  watchers get a `Down`. On wasi, which has no setjmp, a panic still ends
  the program, and watching a death is refused at compile time (#2974).
