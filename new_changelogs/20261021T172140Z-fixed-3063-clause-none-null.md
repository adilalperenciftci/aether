- **A clause set with a `none` clause, a `null` clause and a string or
  pointer clause returns its optional.** `f(0) -> none`, `f(1) -> null`
  and `f(k) -> "s"` was refused ("return string? and `null`, which
  string? does not take"); it returns a `string?` now, `f(1)` the string
  `null` is, as `return null` from a `-> string?` function gives, in any
  order of the clauses. A clause set whose clauses no one type holds is
  reported once; the error was printed twice (#3063).
