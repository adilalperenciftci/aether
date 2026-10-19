- **A `match` is an expression wherever a value goes.** `b = b + match i {
  ... }` never stored the sum, and `c = 1 + match b { ... }` read
  uninitialized memory: `match` was no expression to the parser, which
  stopped at `b +` without a word and kept the declaration with no value,
  while the `match` ran as the next statement. As an argument it was a syntax
  error. A `match` now works as an operand, an argument, a condition (a
  `while` evaluates it on every pass, the right side of `&&` and `||` only
  when it is reached), an interpolation, the subject or an arm of another
  `match`, the value of `+=` or of a field, a `switch` subject, a `panic`
  reason, an actor's state and a `reply`. It runs ahead of its statement,
  in the order written, into a temporary that owns a string or a struct it
  holds. It must give a value on every path that reaches the expression: a
  `_` arm (or arms covering the subject's type), and arms that end in a
  value or leave (#2993).
