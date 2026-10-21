- **A signed and an unsigned integer as one value hold both.** An
  if-expression's branches, a value match's arms and a clause set's results
  that were an int and a uint32 took the uint32, so `if c { -1 } else { u
  }` was 4294967295, and an int or a long beside a uint64 took the uint64 or
  the first of the two. They take the smallest type that holds both now: an
  int beside a byte, a uint8 or a uint16, a long beside a uint32; a literal
  that fits a uint32 or a uint64 beside it is that type (`if c { 0 } else {
  u }` stays a uint32), a clause that returns one as well (`h(0, u: uint64)
  -> 0` beside `h(k, u: uint64) -> u` is a uint64). A signed value beside a
  uint64, which no integer type holds, is E0200 naming both, and beside a
  written uint64 result the error names the written type. A byte beside a
  uint16 is a uint16 (it was whichever came first) (#3064).
