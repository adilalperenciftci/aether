- **Sandbox policies no longer cross thread boundaries.** The in-process
  checker was process-global while generated permission stacks were
  thread-local, so one thread entering or leaving a sandbox block could
  replace or clear another thread's checker. The checker is now thread-local,
  and the preload layer reads it through a weak getter that remains safe when
  no embedded runtime is present.
