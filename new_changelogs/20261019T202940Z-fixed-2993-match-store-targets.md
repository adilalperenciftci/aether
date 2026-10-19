- **A match bound to a module variable or an actor's state stores into it.**
  `g = match o { ... }` for a module `var g` declared a local named `g` that
  hid the variable, which kept its value, and `n = match k { ... }` for an
  actor's state lowered to a GNU statement expression, which the strict C
  path (MSVC) refuses. A bound match now stores each arm's value as `x =
  <value>` stores it, whatever `x` is: a local, a closure's cell, a sum (each
  variant wrapped), a module variable, an actor's state (#2993).
