- **`none` and `[]` through a bare `fn` are refused, not guessed.** Since
  #2840 a closure call wraps an argument into the parameter's optional or
  sum when the closure's parameter types are known. Through an erased call
  (`apply_none(f: fn) -> int { return call(f, none) }`) they are not, and
  the argument's own type stood in for them: `none` was built as an int
  optional ("unresolved type in codegen, defaulting to int"), and given to
  `|o: string?|` or `|o: Big?|` the program crashed. `none` and `[]` given
  through a bare `fn`, as `call(f, none)` or `f(none)`, are now an error
  at the argument; bind the value to a local of the parameter's type and
  pass that. Arguments are coerced only into parameter types a signature
  or the closure literal gives (#2840).
