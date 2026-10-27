- **`for x in xs { ... }` iterates the elements of a slice or fixed array.**
  Only a range (`for i in a..b`) parsed after `in`; an element loop was a
  parse error ("Expected DOTDOT, got LEFT_BRACE"). `xs` can be any `T[]` or
  `T[N]` expression (an `int[]`, a `string[]`, a slice of structs, a call, a
  sub-slice); it is evaluated once, `x` is bound by value with the element's
  type, and `break` / `continue` work as in any loop. It lowers in the parser to
  the existing index loop, so the range form is unchanged.
