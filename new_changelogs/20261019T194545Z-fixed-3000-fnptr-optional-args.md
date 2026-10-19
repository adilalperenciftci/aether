- **A call through a typed function pointer takes an optional argument.**
  For `h = opt as fn(int?) -> int`, `h(4)` failed in C ("incompatible
  type, expected ae_opt_int") and `h(none)` with "expected expression
  before '{'": the arguments went to C as written. They are taken as a
  call through a closure takes them, a bare value or `none` into an
  optional, a variant into a sum, a fixed-size array copied for a `T[N]`,
  for a local, a parameter or a struct field. A struct field of such a
  type was declared before the optional's C type and did not compile
  either (#3000).
