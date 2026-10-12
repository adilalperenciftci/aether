- **A closure returned in a tuple is released by the local it lands in.**
  `f, k = pair(piece)` over `return || { ... }, 1` never released the
  closure's env: the destructure took the slot as a plain value, and the
  tuple position was never asked whether the function hands its closure
  over, so every call leaked the env. A position now hands its closure
  over when every return puts there a closure literal, a call that hands
  one over, a local nobody else keeps, or the same position of a tuple
  call passed on, as a single closure result does (#2494). The
  destructured local releases it at its scope exit, a rebinding releases
  the one it replaces, a closure cell gives the slot's reference back
  once it has taken its own, and a `_` slot gives it back at once. A
  closure the callee only lends (a field it read, a parameter it hands
  back) is left to its owner (#2756).
