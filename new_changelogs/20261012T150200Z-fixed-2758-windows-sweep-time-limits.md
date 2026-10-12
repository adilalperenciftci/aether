- **A hung test on Windows ends as `[TIMEOUT]` without signalling anything.**
  The sweep's time limits were `timeout(1)`, which ends a hung test by
  signalling its process group; on Windows a signal to the MSYS2 process
  standing in for a native program makes the MSYS2 runtime signal unrelated
  processes found through recycled parent pids, the CI step's own `bash`
  among them, and a SIGTERM injects an exit into any native process it
  reaches. On Windows the limits of `run_ae_test.sh`, `run_ae_sh_dir.sh`,
  `run_stage.sh` (and the `-O0`/`-O2` comparison and `make examples-run`) are
  now a job object around the test, which a small native watchdog
  (`tests/lib/sweep_watchdog.c`) ends with TerminateJobObject: the test and
  everything it started go, nothing else is touched, and the result is the
  same 124 (#2758). Linux and macOS keep `timeout(1)`.
