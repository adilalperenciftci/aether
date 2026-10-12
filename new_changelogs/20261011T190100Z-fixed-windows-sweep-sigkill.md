- **The Windows sweep no longer dies with exit code 2304.** A shell test
  that stopped one of its servers sent a signal to the MSYS2 process
  standing in for that native program, and the MSYS2 runtime then signalled
  every MSYS2 process-group leader whose recorded Windows parent pid matched
  the program's. Windows hands pids out again and never rewrites a recorded
  parent, so that reached unrelated processes, the CI step's own `bash`
  among them: the job died with SIGKILL and no test named (#2479). The tests
  now end what they start through `tests/lib/server_jobs.sh`, which on
  Windows ends the program itself with TerminateProcess and signals nothing,
  and `make check-tests` rejects a `kill` of a remembered pid, `pkill` and
  `killall` in shell tests. `ae run` on Windows keeps the program it launches
  in a job object, so ending `ae` ends the program too instead of leaving it
  running with its port bound.
