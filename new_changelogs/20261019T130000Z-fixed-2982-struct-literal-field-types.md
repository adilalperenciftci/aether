- **A struct literal's values are checked against their fields (#2982).**
  `Box { n: "y" }` with a field `n: int` passed the checker and the C
  compiler refused it, while the store `b.n = "y"` was refused. Each value
  now fits its field by the rules a store follows: a conversion, a wrap
  into an optional or a sum, `null` or `[]` into a slice, `null` into a
  string, a named function of the signature into a typed function pointer,
  a byte literal in range. The error names the field and both types.
