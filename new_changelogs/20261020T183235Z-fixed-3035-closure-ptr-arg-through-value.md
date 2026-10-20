- **A closure given to a `ptr` parameter through a function value is
  boxed.** `f = lend` then `f(|x: int| { ... })` passed the closure itself
  where the parameter is a pointer, and the C compiler refused the
  generated call; the same through a local bound to a closure literal. The
  closure is now boxed as a direct call boxes it: on the caller's stack for
  a parameter that borrows, and on the heap with a reference of its own
  where the value's type says the parameter keeps it or hands it to the
  result (`fn(@keep ptr)`, `fn(@into ptr) -> Job`); `release_closure` gives
  that reference back (#3035).
