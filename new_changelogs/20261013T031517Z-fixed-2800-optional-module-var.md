- **A module-level optional `var` can be declared.** `var g: int? = 3` gave
  the file-scope static its value bare, an invalid initialiser for the
  `ae_opt_int` struct; `= none` was refused as not a constant, a struct
  literal was refused for a struct optional, and the constant folder
  re-typed a `string?` with a string value as a plain `string`. The static
  now takes the optional's own constant (`{ .has = 1, .val = 3 }`, `{0}`
  for `none`), and no initialiser means `none`. A function's `g = v`, or a
  tuple destructure slot, writes the global with a bare value wrapped,
  including in a loop body or a closure. A `string?` var takes a string of
  its own and keeps every string it was given, as a `string` var does, so
  whatever reads it (`v = g ?? ""`, `g!`, a `some(v)` binding, a view
  beside a call that re-binds it) stays valid (#2800).
