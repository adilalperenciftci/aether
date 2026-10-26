- **std.sandbox's test suites fail when a case fails.** Both dropped
  `spec.run_summary`'s verdict into a name nothing read, so
  `test_sandbox.ae` exited 0 with five failing cases on Windows, where it
  expected an fs grant's pattern as written and std.sandbox stores it
  resolved as the checks resolve paths (`D:\r\*`). The suites return their
  verdict, the test expects the stored form, and check-tests reports a
  verdict bound to a name nothing reads, as it did a bare call (#3198).
