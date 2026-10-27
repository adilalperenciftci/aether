- **A `@quotable` function that calls itself, directly or through another,
  no longer crashes the compiler.** `aetherc` printed the E0804 "reaches
  itself" error and then overflowed its stack collecting the quote's helpers,
  so it exited with a signal instead of 1. It now stops at the cycle and
  exits 1. The `quote_errors` test also fails on a compiler crash, which
  `ae build` reports as an ordinary failed build.
