- **A local declared without a value starts at its type's zero value.**
  `long x`, `int[3] k` and `P p` were `int64_t x; int k[3]; P p;` in C, so
  reading one before writing it read whatever its stack slot held, with no
  diagnostic. Each is now its zero value (0, false, null, none, the empty
  slice, an array of zeros, a struct of zeros), in a function, a closure
  and an actor's handler, and in a loop body each pass starts it at zero
  again, releasing what an owning one held. Measured on BLAKE2b and
  ChaCha20, whose block functions declare 16-element arrays this way: no
  change outside the run-to-run noise (#3114).
