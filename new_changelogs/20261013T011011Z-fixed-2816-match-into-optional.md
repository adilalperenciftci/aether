- **A `match` bound to an optional takes each arm's value wrapped.**
  `int? o = match n { 1 -> 41  _ -> none }`, its `let o: int? = match`
  form, a `string?` or a struct's optional bound the same way, a re-bind
  `o = match ...` and a `match` returned from a `-> T?` function emitted
  the whole match as one expression inside the optional's wrap (gcc:
  "'n141_' undeclared", "incompatible types when assigning to type
  'ae_opt_int'"). The match is now bound arm by arm, as a match of any
  other type is, each arm's value wrapped into the optional and `none` the
  empty one; a `string?` local owns the arm's string when it is a fresh
  one, as a single-value binding decides (#2816).
