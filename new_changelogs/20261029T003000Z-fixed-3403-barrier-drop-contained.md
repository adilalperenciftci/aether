- **A drop that panics after a handler panicked stays in the step.** When a
  handler panics, its step drops the message it ran on and fires the death
  hook, both after the step's frame is gone. A field's drop function that
  panicked there jumped past the rest of the step: on a core's own thread
  the program ended; stepped inline inside another handler the panic
  landed there, with the inner step's context still put aside, so the step
  lock stayed held (the next ask hung) and an enforce block whose `try`
  caught it ran on with its levels put aside, unenforced. The drop and the
  hook now run in containment frames of their own (`aether_contain`): a
  panic in one is reported through the death hook, and the step gives its
  context back whatever happens (#3403).
