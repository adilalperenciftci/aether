- **A tuple returns into an optional tuple result, and an if-expression
  goes into an optional arm by arm (#2845).** `return (n, n + 1)` and
  `return n, n + 1` from a `-> (int, int)?` function built the bare tuple,
  and gcc refused it. They are now the tuple wrapped into the optional, as
  a binding of a tuple literal is. An if-expression into any optional slot
  (a binding, a return, an argument, a field) was wrapped whole, so
  `if c { 3 } else { none }` was `.val = (c ? 3 : {0})` and a tuple
  literal arm its elements' text run together; each arm is now coerced on
  its own, as a match's arms are. A match arm's tuple into an optional,
  the issue's second case, already worked on main.
