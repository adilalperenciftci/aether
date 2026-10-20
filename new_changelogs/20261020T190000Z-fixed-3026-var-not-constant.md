- **A module `var` is never folded as the constant it starts as.** A `var`
  shares the `const` node, and the compile-time evaluator read it at its
  initializer: a `requires` on a `var` that started true was dropped from
  the C and never checked, one on a `var` that started false refused a
  correct program, a function whose only `return` sat behind `if !flag`
  passed the missing-return check, and W1002 called the code after
  `if !flag { return }` unreachable. Also, an `if` on a `const` no longer
  makes the code after it unreachable for W1002, so a flag that disables
  code on purpose (`if !DEBUG { return }`) is not reported; a loop on a true
  constant with no `break` still is (#3026).
