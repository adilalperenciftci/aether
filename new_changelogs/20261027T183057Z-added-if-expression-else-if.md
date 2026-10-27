- **An if-expression chains `else if`.** `s = if n < 0 { "neg" } else if
  n == 0 { "zero" } else { "pos" }` was "Expected LEFT_BRACE, got IF": the
  else arm had to be braced, so a chain was spelled `else { if ... }`. A
  chain of any length now parses, as an initializer, a return value, an
  argument or an operand, and is the nested form it stands for, so its arms
  type as nested if-expressions do. The final `else` is still required.
