- **`return note(x)` of a function that returns nothing is the call, then a
  return.** Written out in a function or a closure, it was typed int and
  failed in the C compiler ("void value not ignored"). It now means what the
  arrow form `-> note(x)` means: the call, then a `return` of nothing, so it
  fits a function or closure that returns nothing. In one that returns a
  value on another path it has nothing to give back, and is an error naming
  the call (#2733).
