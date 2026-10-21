- **Several literal arms beside an unsigned value are read together.** A
  value match's arms and a clause set's clauses join to a type that holds
  each, and a literal that fits a `uint32` or `uint64` beside it takes that
  type; with several literals only the first was read, so `0`, `-1` and a
  `uint32` (`neg(0, u) -> 0`, `neg(1, u) -> -1`, `neg(k, u) -> u`, or the
  same arms in a `match`) were a `uint32`, and -1 came back as 4294967295.
  The join now reads the literal it must hold most, a negative one, else
  the largest: that set is a `long` (#3064).
