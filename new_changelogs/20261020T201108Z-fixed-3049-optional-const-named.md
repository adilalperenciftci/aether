- **An optional constant may name another.** `const O: int? = none` then
  `const O2 = O`, or `var v = O2`, failed in the C compiler ("incompatible
  types when initializing type 'int' using type 'ae_opt_int'"): the named
  constant, an optional already, was wrapped in another. It is written as
  that constant's own value now, `{0}` or `{ .has = 1, .val = ... }`, which
  every C compiler takes for a static (#3049).
