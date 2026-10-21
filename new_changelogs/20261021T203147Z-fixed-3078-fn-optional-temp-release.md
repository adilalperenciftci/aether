- **A `fn?` a call returns is given back when nothing binds it.** A
  function returning `fn?` hands its caller the closure in it; bound to a
  local the local gave it back, but `maybe(k) != none`, `maybe(k) ==
  null`, a `match` on the call, `maybe(k)!`, `maybe(k) ?? d` and the call
  as a statement leaked the closure's environment at every call (16 bytes
  per call for a closure capturing one int). The expression that reads
  the optional gives the closure back now: a comparison once it is read, a
  `match` at every exit of the arm that binds it, `!` and `??` as a fresh
  closure their place adopts (#3078).
