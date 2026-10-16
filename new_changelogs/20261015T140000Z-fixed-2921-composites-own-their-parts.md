- **Structs, tuples, optionals and fixed-size arrays own what they hold.**
  Each owning type has one generated retain and one drop, used by every
  place: a tuple, optional or array local, a struct or tuple field, a module
  `var`, an array or slice element, a message field, a discard (`_ = v`).
  A tuple local held its strings without releasing them, an alias of it
  shared them, a struct stored into a module `var` leaked the one it
  replaced, an array local rebound in a loop leaked its elements, and a
  store through a slice leaked the element it replaced. A struct parameter
  borrows its caller's value, and one the body writes into is copied on
  entry (#2921).
- **A call through a closure value calls the closure it holds.** A local
  bound to a function's result was taken to hold the closure that
  function's first `return` gave, and was called directly; a function that
  returned another closure on another path crashed (#2921).
