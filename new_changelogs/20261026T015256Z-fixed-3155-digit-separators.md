- **An underscore separates digits in every number literal.** A decimal
  literal stopped at `_`, so `1_000` was the number 1 followed by the name
  `_000` ("Undefined variable '_000'"), and the reference's own `1_000_000`
  and `int[1_024]` did not compile; the `0x`, `0o` and `0b` forms skipped
  every `_` wherever it stood, so `0xFF_`, `0x_FF` and `0b1__0` compiled.
  Now one rule holds in every base, for the integer digits, the fraction,
  the exponent and a duration's digits: an underscore goes between two
  digits, and one at the end, doubled, beside `.` or `e`, or after the
  prefix is error E0100 "misplaced `_` in a number" at the `_` (#3155).
