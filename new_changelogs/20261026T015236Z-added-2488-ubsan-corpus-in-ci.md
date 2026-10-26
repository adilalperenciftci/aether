- **The C unit tests and the whole `.ae` corpus run under UBSan in CI.**
  `make test-ubsan` rebuilds aetherc, ae and libaether with
  `-fsanitize=undefined` and runs `make test` and `make test-ae` with every
  program and C host the tests build going through the same sanitizing
  compiler. It fails on any test failure and any UBSan report, and first
  proves the flags took: libaether.a must call the UBSan handlers, and a
  canary with an undefined shift must be stopped with a report. The new
  `ubsan.yml` runs it on the PRs that touch the compiler, runtime, std, ae or
  the Makefile, nightly and by hand (about 11 minutes). The macOS UBSan step
  of `memory-check.yml` now fails on a report; it used to print it and pass
  (#2488).
