- **INT64_MIN and INT32_MIN emit as C that compiles warning-free.** The
  constant folder turns `(0 - 9223372036854775807) - 1` into the literal
  `-9223372036854775808`, which reached the C as is: `-` applied to a decimal
  that fits no signed type, which clang warns is taken as unsigned and gcc
  as "so large that it is unsigned", both errors under CI's -Werror. Folded
  `(0 - 2147483647) - 1` had the same shape one width down, a `long` that
  `printf("%d", ...)` warned on. Both now emit as `<stdint.h>` spells them,
  `(-9223372036854775807LL - 1)` and `(-2147483647 - 1)`, and so does a
  `@derive(schema)` attribute argument of the minimum.
