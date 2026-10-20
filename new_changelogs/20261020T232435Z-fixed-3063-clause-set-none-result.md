- **A clause that returns only `none` joins its set's result as `T?`.** In
  `find(0, n: int) -> none` with `find(k, n: int) -> n + k`, the `none`
  clause had no type of its own, so the set never settled and took the
  other clause's `int`, and the C compiler refused the `none`. Such a
  clause now joins the others' `T` as `T?`, as an if-expression's `none`
  arm does; a set whose every clause returns `none` is E0200 asking for the
  `T`, and one beside a written `T` that is no optional is E0200 naming
  `-> T?` (#3063).
