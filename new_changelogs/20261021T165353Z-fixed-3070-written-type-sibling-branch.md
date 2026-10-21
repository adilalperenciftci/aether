- **A type written for a local bound in several branches is its type.**
  `uint64 x = 7` in one branch and `x = n` (an int) in another was refused
  in that order and compiled as an int in the other; `x = -1` beside it
  printed -1, and `int x = 0` beside `x = 1.5` made `x` a float. The
  written type is the local's type now, in either order: a binding of a
  value it holds binds (`x = 5` beside `uint8 x = 7`), and one it does not
  hold, or one that writes another type, is a compile error at that
  binding (#3070).
