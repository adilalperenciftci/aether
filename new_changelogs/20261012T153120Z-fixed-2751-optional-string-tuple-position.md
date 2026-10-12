- **A `string?` in a tuple a function returns is its caller's own.** A
  fresh string returned in a `string?` position (`return
  string.concat(w, "x"), 1`) leaked on every call: the destructure
  `a, n = two(w)` took it with the local's ownership flag left 0. Each
  `string?` position of a named function's or a closure's tuple now hands
  over a string of its own, as a single `string?` result does (#2740): a
  fresh one or an owning local's as it is, a parameter, a literal or a
  field copied, `none` as nothing; a whole tuple passed on from a C
  function or a closure the compiler cannot name is copied the same way.
  The destructured local owns it and frees the string it replaces, a `_`
  slot frees it at once, and a `string?` parameter a tuple return copies
  no longer keeps its caller's argument (#2751).
