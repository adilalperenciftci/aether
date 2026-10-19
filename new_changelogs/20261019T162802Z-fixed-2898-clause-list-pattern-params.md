- **A list pattern can be a clause's parameter.** `lp([h | t], b: *Box)`
  failed with "Undefined variable 'h'" and "expects 1 argument(s)", and
  `sum([h | t])` alone with "expects 0": the checker counted no list
  pattern as a parameter and bound none of its names, and codegen took it
  as a pointer and a length that no call passed. A list pattern parameter
  now takes a slice (an array is viewed as one, `[]` is the empty one); a
  clause runs when the length fits (`[]`, `[x, y]`, `[h | t]` for one or
  more) and a literal element is equal (`[0 | t]`), and its names are
  bound, an element as a value and a cons pattern's tail as the slice of
  the rest, in the clause's body and its guard. The element type is the one
  the calls pass, or another clause's typed parameter at that position,
  else `int`. Call-site type inference also reads a parameter after a
  `where` contract at its own position (#2898).
