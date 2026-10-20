- **A pointer computed from a borrowed `ptr` parameter is the parameter.**
  `kept = p + 8`, `return p - 1` and `n.child = p + 16` kept a borrowed
  `ptr` parameter, or let an `@into` one reach somewhere other than the
  result, with no E0902, since the check followed the pointer through casts
  but not through arithmetic. `p + n` and `p - n` now carry what `p`
  carries: an `@into` function may return `p + 8`, and at a call the result
  plus an offset still holds the argument (#3033).
