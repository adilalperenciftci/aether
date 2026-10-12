- **A `fn` variable a closure rebinds releases its closures.** A variable a
  closure writes lives in a shared cell, and a `fn` one took its first value
  without a reference of its own and never gave back any closure it held:
  4400 bytes per 100 calls of a function whose nested closure rebinds its
  `fn` parameter, 9200 for a local rebound the same way. The cell now holds
  a reference to its closure, as a field or a global does: its first value
  and every store are taken (a parameter's retained, so the caller still
  releases the closure it passed), a store gives back the one it replaces,
  and the cell's last holder gives back the last. A call through the cell
  holds the closure for the call, so one that rebinds its own cell while it
  runs is not freed under itself. A cell whose value a `return` or a keeping
  callee may hold bare keeps every value for good, as before (#2755).
