- **A function passed by name to an extern's `fn(...)` parameter is the C
  function pointer.** `apply(on_int, 2)`, with `extern apply(handler:
  fn(int), v: int)`, named an adapter `_aether_bare_adapter_on_int` that was
  never emitted (gcc: undeclared), and would have handed C a closure struct
  where it reads a function pointer; only `on_int as fn(int)` worked. A typed
  fn-pointer parameter of an extern now takes the function's address, as the
  cast does (#2677).
