- **A literal clause fits a written result type that holds its value.**
  `g(0) -> 5` beside `g(k) -> uint8 { ... }` was refused as an `int`,
  which `uint8` does not hold, while a literal bound beside a local's
  written type is taken. A literal clause is held as a binding is now;
  `300` beside `-> uint8` is still refused (#3082).
