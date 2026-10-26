- **An arrow body may follow a written result type.** `square(x: int) ->
  int -> x * x` was read as a result type and a block body: "Expected
  LEFT_BRACE, got ARROW", after which the block parser read the rest of the
  file as the missing block's statements, nine errors reaching later
  functions' parameters. `-> T -> expr` and `-> T -> { ... }` (contract
  clauses may sit between) are now an arrow body returned against `T`, as a
  block body's `return` is, so a value of another type is one E0200 at the
  value (#3158).
