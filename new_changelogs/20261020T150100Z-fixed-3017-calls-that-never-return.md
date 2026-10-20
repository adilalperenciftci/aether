- **`exit(n)` leaves wherever a statement may leave.** An `or { }` handler
  ending with `exit(n)` compiled to invalid C (`exit` was taken as the
  block's value), a value `match` arm calling it was refused as an arm with
  no value, and an `if` expression branch made of it, or of any call that
  returns nothing, reached C as a void operand of `?:`. Whether a statement
  leaves is now decided by one rule, the missing-return analysis, for the
  `or` handler, a value `match` arm, the isolation check and W1002: a
  handler or arm ending in `exit(n)` or `os.exit(n)`, or in an `if`/`else`
  or `match` every path of which leaves, needs no value; an `if` expression
  branch with no value is error E0200 naming the forms that can leave; and
  W1002 now also flags code after `break`, `continue`, `panic` and a loop
  nothing ends, naming the statement (#3017).
