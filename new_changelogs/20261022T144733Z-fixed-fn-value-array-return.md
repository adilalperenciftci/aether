- **A named function is a value in an array literal and after `return`.**
  `[held, null]` was typed as an int array, and C got `int fs[2] = {held,
  NULL}`; `return held` from a `-> fn` function called an adapter nothing
  had declared. Both are function values now, as an argument or a local's
  value already was: `[held, null]` is an array of closures, and the
  returned function is the closure a caller calls. Where the place is a
  typed function pointer (a `cfn` result, a part of a tuple result, an
  array of one such as `let ops: Op[2] = [twice, half]`), the function is
  its address there instead.
