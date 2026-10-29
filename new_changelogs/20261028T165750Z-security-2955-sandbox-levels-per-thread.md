- **A sandbox's grants belong to the thread that entered them, in the
  runtime.** Every `sandbox.enforce` installed one process-wide checker
  pointer, and any thread leaving its block cleared it: a deny-all block on
  one thread then ran unchecked while another thread entered and left an
  allow-all block, or called the pointer just cleared and the process died
  of an access violation. The grant levels lived in each program's or
  library's generated code, so a library's export called from inside
  another library's block checked against an empty stack of its own, or,
  on one runtime, replaced the outer checker with its own (an inner
  `grant_all` widened the block) and cleared it on the way out (the rest of
  the block ran unchecked). A panic caught by an actor's barrier left the
  block's level on the scheduler thread, so the next handler there was held
  to grants already freed; and a 65th nested level was silently dropped,
  its pop taking an outer level off. The levels are now each thread's,
  kept by the runtime (`aether_sandbox_push` / `aether_sandbox_pop` for a C
  host): nesting across libraries on one runtime narrows; libraries with
  copies of the runtime of their own (macOS, Windows, built without
  `--shared-runtime`) refuse what they cannot check, naming
  `--shared-runtime`; a caught panic ends the levels pushed inside its
  frame, whoever catches; a 65th level is refused with a panic. The contrib
  host bridges push their grants as levels of the thread instead of
  swapping the checker, so a bridge inside a block gets the intersection,
  and the LD_PRELOAD library reads the calling thread's levels.
  `sandbox_install()` and `sandbox_uninstall()` now do nothing (#2955).
