- **A quote's tree names the unsigned types, and a literal beside a
  `uint32` is one.** A `uint32`, `uint16` or `uint8` node was typed
  `UNKNOWN` in the tree, so a shader back end could not write ae3d's
  radical-inverse bit twiddling, and `bits & 0xAAAAAAAA` was a `long`, the
  literal being past `int`. The tree now spells them `uint32`, `uint16`,
  `uint8`. An integer literal that fits (0 to 0xFFFFFFFF) beside a `uint32`
  in `&`, `|`, `^` or a comparison takes the `uint32`, in a quote and
  outside one, where its value cannot change: `b = x & 0xFFFFFFF0` now
  infers `b` as a `uint32`, as `x & 0xF0` already did. Arithmetic and shifts
  are unchanged (`x + 0xFFFFFFFF` is still a `long`). `quote.VERSION` stays
  2: type names are not kinds.
