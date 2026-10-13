- **Returning the `some(s)` binding of a `string?` local no longer returns
  freed memory.** The binding was a view of the local's string, which the
  local freed at scope exit before the caller read it, through `return s`
  or a tuple's `return s, 1`. The binding is a copy the arm owns now, as
  over a closure cell, and both returns hand it over; an owned binding at
  a tuple position counts as a heap return as it does at a single one
  (#2835).
