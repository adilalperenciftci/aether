- **A local bound from a call in a cycle of inferred results has its
  type.** In `x(p, k) { if k > 0 { r = y(p, k - 1); println("${r}") };
  return p.big }` with `y(p, k) { return x(p, k) }`, `y` was checked after
  `x`, so `r` was typed while `y`'s result was unknown and printed
  5000000000 as 705032704. A function whose first value `return` reads
  only its parameters, or calls of functions already typed, has its result
  before its body is checked, so the callee is checked first (#3069).
