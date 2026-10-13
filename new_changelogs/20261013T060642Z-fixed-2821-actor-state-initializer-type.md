- **An actor state initialized by an `or` has the type of its value.** The
  typechecker took the type of a state's initializer only when it was a
  plain call, so `state name = word(true, "q") or { "dflt" }` left the field
  untyped: codegen declared it `int`, and the program did not compile (a
  string assigned to an int, an int passed to `string.length`). An int
  field compiled, with warnings, but its uses in the handlers were untyped.
  Such a field now has the type its initializer infers to (#2821).
