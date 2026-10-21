- **A function that returns `none` and a value returns an optional.** With
  no result type written, `g(p: *H, k) { if k == 0 { return none }; return
  p.n }` was typed `int` by its later value: the `return none` failed in
  the C compiler, and `g(h, 1) ?? 0` was refused. It returns `int?` now, as
  a clause set with a `none` clause and an if-expression with a `none` arm
  do, wherever the `none` stands, and whether or not the early inference
  pass could type the value (#3068).
