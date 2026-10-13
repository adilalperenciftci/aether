- **The empty literal `[]` in a `T[]` slot is the empty slice.** A slice is
  an AetherSlice struct in C, and the checker turned a `T[N]` array or `null`
  in a slice slot into one, but not `[]`: `let xs: int[] = []` reached C as
  `AetherSlice xs = NULL` ("invalid initializer"), and an argument, a
  `return`, a re-bind or a struct field as `{}`. `[]` is now the empty slice
  wherever a `T[]` is expected, as `null` is: `.len` is 0, it views no
  storage, and it compares equal to `null` (#2767).
- **A module-level `T[]` takes the empty slice.** `var gs: int[] = null` was
  a call in a static initializer ("initializer element is not constant"),
  `const E: int[] = null` or `= []` was emitted as a C array, `var gs:
  int[] = []` was refused as not constant, and `gs = []` in a function
  reached C uncoerced. Each is now the constant empty slice, and a bare
  re-bind of a module-level `T[]` var is checked and coerced against the
  global's type (#2785).
