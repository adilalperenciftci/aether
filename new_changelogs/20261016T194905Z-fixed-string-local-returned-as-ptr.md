- **A string local returned from a function whose result is a `ptr` is
  handed to the caller, not freed first.** A function with no result type
  takes the type of what it returns, and a string local re-bound from a
  `ptr @heap` extern (`out = "x"`, then `out = string.from_int(n)`) gives it
  `ptr`. The return moved a local out only for a `string` result, so here it
  returned the local as it was and the local's scope exit freed it before
  the caller read it: the caller got freed memory (`''` or garbage) since
  0.818.0. The return now moves the local out whatever the result's type,
  as a `string` return does: an untyped return, a `-> ptr` one, an early
  return and a tuple position. Found by aeb's toolchain-selection tests.
