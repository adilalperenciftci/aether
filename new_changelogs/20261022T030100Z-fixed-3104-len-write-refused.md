- **A write to `.len` of a slice or an array is a type error.** `xs.len = 2`,
  `xs.len += 1`, `xs.len++` and `a.len = 3` on an array passed the checker
  and failed in the C compiler on generated code ("lvalue required"). The
  checker refuses each with its own message and points at `xs[lo..hi]` for
  fewer elements (#3104).
