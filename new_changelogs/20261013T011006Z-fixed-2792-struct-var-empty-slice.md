- **A module-level struct `var` takes `[]` or `null` for a `T[]` field.**
  The field's empty slice was not taken for a constant, so `var g: S = S {
  xs: [], n: 1 }` was refused as not a compile-time constant; it is now the
  constant `{0}` in the struct's static initializer, as for a `T[]` global
  (#2792).
