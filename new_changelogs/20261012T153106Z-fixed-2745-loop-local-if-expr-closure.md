- **A loop's local bound by an if-expression or a closure call, read before
  its binding, has the binding's type.** The inference pass that types a
  loop's locals before the checker declares them ahead of the loop typed
  neither an if-expression nor a call through a local bound to a closure
  literal, so `out = "${out}${prev}"` ahead of `prev = if i > 0 { "x" } else
  { "y" }` (or `prev = call(f)` with `f = || -> "z"`) printed pointer values
  as ints. It now types an if-expression by its arms, as the checker does,
  and a call of a closure literal, directly or through a local every binding
  of which is such a literal, by what the literal returns (#2745).
