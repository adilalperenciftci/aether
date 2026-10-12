- **A std.spec suite's failures reach its exit code, and the docs say how.**
  `docs/testing.md`, `CONTRIBUTING.md` and the example in `std/spec`'s
  header ended a suite with a bare `spec.run_summary(fw)` and said it exits
  1 on failure; it returns the verdict and does not exit, so a suite written
  that way exits 0 with failing cases and `ae test` reports it as passing.
  The examples now `return spec.run_summary(fw)`. Nine of the repository's
  own suites (seven in `contrib/jq`, two in `std/jsonpath`) were written the
  bare way and could not fail; they return their verdict now (all pass),
  and `make check-tests` rejects a suite that drops it (#2678).
