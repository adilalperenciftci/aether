- **A hung test on macOS ends as `[TIMEOUT]` instead of holding the CI job.**
  The sweep bounded each test and each `make ci` stage with `timeout(1)` or
  `gtimeout`, and ran it with no limit where neither exists. GitHub's macOS
  runners ship no coreutils, so there every `.ae` test, shell test and stage
  ran unbounded: one hang held the job until GitHub's 6 hour ceiling, and a
  run cancelled after 40 minutes left no log naming the test. Where neither
  tool exists the bound is now perl, which every macOS has, with
  `timeout(1)`'s behaviour: the command runs in a process group of its own,
  which gets SIGTERM at the limit and SIGKILL after the grace period, and
  the status is 124 (137 when it had to be killed). The `ci` matrix and the
  Windows sweep jobs also carry a job-level `timeout-minutes`, and the CI
  legs split in two give the job that runs all of `make ci` a third of the
  sweep instead of half, so both halves finish together (#2772).
