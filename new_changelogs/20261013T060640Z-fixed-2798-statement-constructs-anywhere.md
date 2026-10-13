- **An `or` with a block, a propagating `!` and a trailing-block call are
  plain C wherever they are.** On the path `AETHER_GCC_COMPAT 0` selects
  (what cl.exe compiles), these constructs, which run statements, were GNU
  statement expressions anywhere but the first thing their statement
  evaluates: after another operand (`y + (f() or { -1 })`, a second
  argument), in a loop condition, behind `&&` or `||`, in a branch of an
  `if` expression or the default of `??`, in a compound assignment, a
  struct literal's field, a `for` loop's init or increment, a `match` arm's
  value, an actor state's initializer, and in a statement that keeps the
  structs its calls return in temporaries. Each now runs as statements
  ahead of its statement, after whatever the statement evaluates before
  it, which is evaluated into temporaries first, in source order; one in a
  conditional part runs under the same test, and one in a loop condition at
  the top of every pass. A builder's arguments are evaluated after its
  block, left to right, whether the call is a value or a statement of its
  own; as a value, an argument holding one of these constructs ran before
  the block. Nothing in the .ae sweep, or in programs written to reach each
  of these places, is a statement expression on that path any more
  (#2798).
