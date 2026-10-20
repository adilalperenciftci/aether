- **E0900 follows a closure call's re-binds.** `reset = || { v =
  make([]int, 4) }` then `reset()` left `v` holding the slice of the
  function's storage it held before the call, so `return v` was refused
  though `v` held the `make` buffer. A call of a closure the function binds
  now counts what the closure re-binds for sure: a name of the function the
  body binds on every way through it before any `return` (both branches of
  an `if`, every arm of a covering `match`, not a loop's body), told apart
  from the closure's own names by binding rather than spelling, and only
  when the closure is the one the name holds at the call. A store of a view
  the closure may make still taints the name from where the closure is
  written on, so the call only takes views away. A `try`'s handler now
  starts from the state after any statement of its body, not only its end:
  `v = arr` then a re-bind that panics left the slice standing, and that was
  accepted (#2837).
