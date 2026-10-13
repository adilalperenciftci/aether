- **`int k = match n { ... }` binds the match's value.** The C-style typed
  declaration parsed its initializer as an expression, and `match` is none,
  so `k` was declared with no value and the match ran as the next statement
  with its values dropped: `k` read whatever the stack held. It now takes
  the match as its value, as `k = match` and `let k: int = match` do
  (#2790).
