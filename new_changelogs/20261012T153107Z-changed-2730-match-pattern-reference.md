- **The language reference lists every `match` pattern.** Match Expressions
  named only integer and string literals, `_` and list patterns. It now lists
  each kind (literals, a variable or constant name, ranges, comma-lists,
  `_`, enum members, sum variants, `none` / `some(v)` and list patterns),
  what it matches and over what, with runnable examples, and the errors an
  arm the value cannot match gives (#2730).
