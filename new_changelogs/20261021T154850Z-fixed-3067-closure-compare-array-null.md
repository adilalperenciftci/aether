- **A closure compares only with `null`, and `null` in an array literal of
  closures is the empty closure.** Since 0.837.0 a closure compares with
  `null` and takes it (#3062); `f == g` between two closures, or `f == p`
  with a pointer, still passed the checker and C refused it (`invalid
  operands to binary ==`). It is E0200 now, `a closure compares only with
  null` (Go's rule for function values: the same function over another
  environment is another closure); a typed C function pointer still
  compares as C's pointers do. `[f, null]` reached C as
  `_aether_closure_retain(NULL)`, and `[null, f]` was an array of pointers:
  `null` and `none` have no type of their own in an array literal now (the
  first element that is neither decides, so `[none, x]` is an array of x's
  optional, where it was refused), and each element goes into a slot of the
  element type, so `null` is the empty closure, the null string or the null
  pointer there. An element the type cannot hold, `[1, "x"]` or `[p, null]`
  with `p` a struct, is E0200 at the element; it reached C as an
  initializer of the wrong type (#3067).
