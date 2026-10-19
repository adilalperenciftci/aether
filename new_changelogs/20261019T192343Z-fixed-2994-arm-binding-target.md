- **A match's value reaches the variable it is bound to when an arm binds
  that name.** `v = match o { some(v) -> v  none -> 0 }` left `v` as it
  was: the arm's binding was a C local of the same name in the arm's block,
  where the match's value was written, so the binding took it. A struct
  pattern's or a list pattern's name did the same, and one named like a
  variable a closure writes did not compile. Each name an arm's pattern binds
  that the function names elsewhere is renamed in its arm, as a scoped
  string binding is (#2746), so it stays the arm's own and the value goes to
  the variable outside, a local, a closure's cell, a module variable or an
  actor's state (#2994).
