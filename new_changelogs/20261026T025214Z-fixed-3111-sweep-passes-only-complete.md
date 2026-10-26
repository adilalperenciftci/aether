- **`make test-ae` passes only when every test it listed reported.** On a
  Windows machine that stopped starting processes mid-sweep (forks failing
  with STATUS_DLL_INIT_FAILED_LOGOFF), most shell tests never ran, the
  sweep's xargs still returned 0, and the sweep counted only the markers it
  had. The sweep now writes the units it hands its runners to a list, names
  every listed test that left no PASS, FAIL or SKIP marker under `=== TESTS
  THAT NEVER REPORTED ===` and in `build/test-ae.unreported`, and fails. Its
  verdict (`build/test-ae.verdict`) carries the listed count, which
  `sweep_verdict.sh` holds the total to. One sed expression
  (`tests/scripts/sweep_name.sh`) names a test for the runners and for the
  check (#3111).
