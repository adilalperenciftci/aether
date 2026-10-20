- **A pointer moves by an integer of any width.** `p - n` with a `long`
  n was refused (E0200 "Type mismatch in variable initialization"), as
  were `p + n` and `n + p` with a `long` bound to a local, while an `int`
  n passed. A pointer plus or minus an `int`, a `long`, a `uint32` or a
  `byte` is a pointer now, and `-=` / `+=` on a pointer local take any of
  them. A number less a pointer, `n - p`, which reached the C compiler as
  "invalid operands to binary -", is the checker's error (#3045).
