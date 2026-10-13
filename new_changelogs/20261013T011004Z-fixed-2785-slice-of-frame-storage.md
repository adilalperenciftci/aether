- **A slice of a function's own storage can no longer leave the function.**
  An array literal in a slice slot and a function's own fixed-size array live
  in its frame, so a slice of either that left the function viewed memory
  the next call reused: `gs = [11, 22, 33]` in `fill()`, then any call that
  filled its frame, read `gs[0]` as 0, and a returned slice of a local array
  read garbage the same way. Each way such a slice leaves the function is
  now error E0800 at the value that leaves: a return (alone, in a struct or
  tuple, or in a closure that captured it), a store to a module-level `var`,
  and a store to a field of a struct behind a pointer or of a global. A
  fixed-size array parameter is the function's own copy, so a slice of it
  is refused the same way. What a name holds where it leaves decides: a
  local or a local struct's field re-bound to a `make` buffer before it
  leaves is accepted, also by a call of a local closure that re-binds it on
  every path through its body, and one that still holds the frame's storage
  on any path to the exit is not. A slice used while the function runs, passed down to
  a call, or of a slice parameter or a `make` buffer, is unchanged (#2785).
