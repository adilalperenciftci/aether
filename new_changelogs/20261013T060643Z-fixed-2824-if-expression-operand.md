- **An `if` expression used as an operand has its own value.** It was
  written as a C conditional with no parentheses around it, and `?:` binds
  looser than any operator, so `y + (if c { 10 } else { 20 })` computed
  `(y + c) ? 10 : 20` and `(if c { 10 } else { 20 }) * 2` doubled the
  else branch only. The conditional is now parenthesised whole (#2824).
