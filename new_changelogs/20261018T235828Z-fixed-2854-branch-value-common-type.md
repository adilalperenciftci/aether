- **An if expression and a value match have their branches' common type
  (#2854).** Each took the type of its first branch, so a wider value in
  another one was narrowed into it: `v = if c == 1 { 1 } else { big }` with
  a `long big` declared `v` an `int` and printed 1705032704 for 6000000000,
  and `if c { 1 } else { 2.5 }` truncated the float. Two numeric branches
  now join as C's `?:` computes their type (a `long` over an `int`, a
  `float` over either), and a float literal beside an `f32` branch takes the
  `f32`, as it does beside an `f32` operand.
