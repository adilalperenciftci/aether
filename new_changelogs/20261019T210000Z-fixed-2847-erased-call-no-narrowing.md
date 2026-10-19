- **An erased call reaches no closure by narrowing an argument (#2847).**
  The dispatch that coerces a call through an erased `fn` took as a target
  any closure whose parameter converted the argument, narrowing too:
  `call(f, 0.5)` gained a branch calling `|a: int|` with 0.5, which clang
  warned at ("implicit conversion from 'double' to 'int' changes value"),
  in the output of the program that built through it. A target now takes
  each argument by the assignment rules without narrowing, and a widening
  it needs (an int into a `long` or a `float` parameter) is an explicit
  cast, so no C compiler warns.
