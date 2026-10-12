- **A single expression arrow body may start with a field.** A dotted name
  after `->` was always read as a qualified return type, so
  `get(p: *P) -> p.n` and `store(p: *P, v: int) -> p.n = v` were parse
  errors ("Expected LEFT_BRACE"). The name is a return type when the `{`
  body, a `requires` / `ensures` clause or a type suffix follows it, as
  in `-> geo.Point { ... }`, and an expression body otherwise.
