- **A C-style `for` loop variable that a closure in the body writes is the
  closure's.** `for (i = 0; i < 6;) { bump = || { i = i + 2 } ... }` did
  not compile: the closure keeps `i` in a cell it shares, which the
  condition, the increment and the body read through, but the `for` header
  declared a plain `int i` (gcc: invalid type argument of unary '*'). The
  loop now declares the cell as any other such local: one cell for every
  iteration, as `i = 0` before a while gives, released after the loop, so
  the loop prints what its while-loop rewrite prints, and a closure that
  outlives the loop keeps the cell (#2737).
