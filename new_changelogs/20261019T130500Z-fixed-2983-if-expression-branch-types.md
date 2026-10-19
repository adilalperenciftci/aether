- **An if expression's branches give a value of one type (#2983).** Two
  branches neither of which takes the other's type, an `int` and a
  `string` or two variants of a sum, passed the checker and failed in C's
  `?:`. They are now refused, naming both types. Numbers still join to
  their common type (#2854), and a branch the other one's type takes (a
  variant beside its sum, an `int` beside a `long?`) is converted into it:
  the expression has the wider type, where `if c { sh } else { Circle {
  r: 2.0 } }` with a `Shape` was a C type mismatch.
