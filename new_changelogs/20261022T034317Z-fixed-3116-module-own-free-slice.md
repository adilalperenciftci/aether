- **A module that defines its own `free` can free a slice.** The merger
  renames a module's calls to its own functions, so in a module defining
  `free(p: ptr)` (`bignum.free`, `json.free`) every `free(xs)` called that
  function: a slice decayed to its pointer, the module read it as its own
  object and crashed, and the builtin that releases a `make` buffer was
  out of reach. A slice argument now goes to the builtin unless the
  module's `free` takes a slice itself (#3116).
