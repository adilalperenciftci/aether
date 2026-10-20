- **A statement that ends before its value no longer compiles.** `main() { x
  = }` compiled, with W1001 and "unresolved type in codegen, defaulting to
  int", and so did `int x =`, `x = ;`, `y = x +`, `x = -`, `x = f(`,
  `return 1 +`, `return a,` and `[1, , 2]`: the expression parser gave up
  without a word at a token that cannot begin an expression, and the `=` or
  operator before it was taken as having no value. Each is now E0100 at the
  `=` or operator, naming what was expected and what was found
  (expected a value after `=`, found `}`), and the rest of the line is not
  reported again. A bare `return` in a function whose written result is a
  value, which reached C as `return;` (GCC 14 refuses it), is E0200 (#2998).
