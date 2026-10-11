- **A closure's arrow body `|x| -> { ... }` returns its last value.** It was
  parsed as a plain block, so `|x| -> { x + 1 }` returned nothing and using
  its value failed in the C compiler ("invalid use of void expression"). It
  now follows a function's `-> { ... }` rule: the last expression is returned
  as the bare expression (#2685), and a trailing statement is not a value
  (#2694). Neither is a call of a function that returns nothing: an arrow
  body ending in one, `-> { note(x) }` or `-> note(x)` for a function or a
  closure, ends with the call and returns nothing, where it emitted a C
  return of a void value that did not compile (#2697).
