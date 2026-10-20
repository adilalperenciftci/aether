- **A call that returns nothing gives no value anywhere.** Only a local's
  initializer was checked (`x = g()` with g returning nothing is E0200), and
  only for a callee named without its module. A field or element store, an
  argument, an operand, an interpolation, an array, tuple or struct literal,
  an index and a compound assignment all reached C, which refused them as an
  "invalid use of void expression", and `x = print(1)` compiled. Each is
  E0200 at the call, naming it and the place ("'g' returns no value, so
  there is nothing to pass here"), and a local refused that way is still
  bound, so its uses report nothing more.
