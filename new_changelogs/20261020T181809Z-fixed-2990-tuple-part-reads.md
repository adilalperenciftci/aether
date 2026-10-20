- **A part read out of a tuple holds only what went into that part.** Since
  E0902 began following a borrowed `ptr` parameter into tuples, a tuple
  local counted as holding it in every part, so `t = (p, malloc(8))`, then
  `a, b = t` and `return b`, was refused though `b` is the function's own
  block. A tuple built from parts now records which part holds the
  parameter, nested ones included, and a destructured part carries only
  that; a tuple that comes whole from elsewhere (a call's result) still
  holds it in every part (#2990).
