- **A `defer` runs when a caught panic leaves its scope.** The language
  reference says a plain `defer` runs on every exit; a panic skipped it, so
  `defer list.free(l)` in a `try` body, or in a function a panic passed
  through, leaked the list. While its scope is live a plain `defer` is now
  in the unwind journal, and a panic runs it there, newest first, over the
  locals as they are at that moment (#2923).
- **A caught panic releases each owning array, cell and argument.** A
  `string[N]` or struct array local, a variable a closure writes (its
  shared cell), an argument a call holds for its duration, and an `x!`
  error string handed to the catcher were not released when a panic left
  them (#2923).
