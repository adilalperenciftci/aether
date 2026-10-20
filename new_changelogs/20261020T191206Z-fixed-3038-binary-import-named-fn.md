- **A named function goes to a binary import's closure parameter.** A
  library exporting `run(cb: fn, n: int)`, imported as a binary, then
  `run(my_fn, 3)` with `my_fn` a named function, stopped in the C
  compiler on `_aether_bare_adapter_my_fn` undeclared, whatever the
  parameter's modes; a closure literal worked, and so did a source import.
  The adapter a named function goes through is now declared ahead of the
  code for an extern's `fn` parameter, a binary import's stub among them,
  as for an Aether function's (#3038).
