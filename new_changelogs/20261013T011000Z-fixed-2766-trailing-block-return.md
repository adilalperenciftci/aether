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
