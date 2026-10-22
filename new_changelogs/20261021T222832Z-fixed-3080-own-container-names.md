- **A program's own function named like one of std's container stores is
  called as itself.** A program's `list_add(xs: ptr, f: fn)` was compiled
  as std's closure store (`_aether_list_add_closure`) and failed in the C
  compiler, and its own `map_put` given a string as std's owning store.
  `list_add` and `map_put` are std's C functions now (#3086), so a program
  function of either name gets a C name of its own, as one named like any
  other std C function does (#3080).
