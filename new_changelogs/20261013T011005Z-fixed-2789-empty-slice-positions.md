- **`[]` is the empty slice in an if-expression or match arm, in a
  comparison and in a C function's `T[]` parameter.** An if-expression or a
  `match` given to a `T[]` was coerced as one value, so a `[]` arm stayed an
  array initializer (gcc: "invalid initializer", "invalid use of void
  expression"), and a `match` of arrays into a slice was not valid C at all.
  Each arm now goes into the slot on its own. `s == []` compared the slice
  with `{}`; the empty slice views no storage, so it is now `s == null`
  (test `s.len == 0` for emptiness). A C function's `T[]` parameter given
  `[]` had `{}` in its call; it now gets the null pointer (#2789).
