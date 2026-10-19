- **`ae fmt` keeps `or (x)`, a line-leading `-2` and `f()! + g()!`.** The
  formatter wrote `x or (y or { 1 })` as `or(y ...`, which reads as a call
  of a function `or`; a block's last line `-2` as `- 2`, which reads as the
  end of a subtraction from the line above; and `small(3)! + num(true)!` as
  `small(3)! +num(true)!`. After a value `or` is the error handler's
  keyword and keeps its space before a parenthesis; an operator that begins
  a line is a prefix one, since the parser never continues an expression
  with an operator on a new line (a line-leading `*` already was); and a
  `!` written tight after a value is its postfix unwrap, which ends a value.
  Five tests in the tree spelled with the old output are reformatted
  (#2818).
