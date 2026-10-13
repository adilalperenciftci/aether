- **A `return` in a call's trailing block counts as one of the function's
  returns.** The block, `f(x) { ... }`, runs inline, so its `return` returns
  from the function around it, but every pass that asks what a function
  returns stopped at it as at a closure: codegen's `has_return_value`, the
  checker's mirror, the settle of which functions return a value, return-type
  inference and the heap-string return walks. A function with no written
  result type whose only value `return` was in such a block was emitted
  `void` (gcc: "'return' with a value, in function returning void"), and a
  binding of its call was refused ("returns no value"); a closure likewise.
  The block is now part of its function everywhere: the function returns the
  value, typed from it, a path that runs off the end after such a return is
  the missing-return error, the checker checks the `return` against the
  function's result type (a bare enum member there was "Undefined
  variable"), and a bare call returned from a member-access call's block is
  settled through the block's receiver (`return note(n)` in `blk.run() { }`
  is `blk.note`), as the checker resolves it (#2766).

  Such a call is the receiver's function before a function of the program or
  a local of the function of the same name, in every pass alike: beside a
  program's `note(n: int) -> int`, inference typed `return note(n)` by that
  `note`, so the function was declared `int` around the bare `return` the
  checker made of it; the module prune also dropped `blk.note` when a local
  was named `note`. Since a return in a block now gives the function its
  type, some programs print otherwise than before: a function with no written
  type whose first `return` gives an int inside a block and a later one
  `return 2.5` returns 2, as it does with the first `return` outside a block,
  and a `long` returned from a block is no longer cut to an int.
