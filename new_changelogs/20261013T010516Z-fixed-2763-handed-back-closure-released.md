- **A closure passed to a function that hands it back is released.**
  `g2 = keep(g)` over `keep(f: fn) -> fn { return f }`, or
  `g2, m = pair(g)` over `return f, 5`, leaked the closure's environment
  on every call: passing `g` counted as a keep, since the callee returns
  its parameter, so `g` stopped owning its env at the call, and `g2` was
  bound to a value someone else held, so it never started. Such a call is
  now the argument itself: a plain local bound to it, or a tuple slot it
  hands the argument back at, is an alias that retains, as `g2 = g` does
  (#2668), and the argument is judged where the call's value goes, as the
  name would be (a store, a cell, a `_` slot, another call). The same
  holds through a function that returns `keep(f)`, for `return keep(g)` of
  a local, whose caller now owns the closure, and for a closure literal
  passed to a function that binds its parameter so, which the caller now
  releases after the call (#2763).
