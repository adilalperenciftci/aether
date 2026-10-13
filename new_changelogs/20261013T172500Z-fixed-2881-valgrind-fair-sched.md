- **Every Valgrind run in CI and the Makefile uses `--fair-sched=yes`
  (#2881).** The massif profiling job ran on Valgrind's default lock, which
  lets a busy-waiting thread keep it while the thread it waits on starves
  (#2593), so the scheduler teardown test took from 4 to 76 s there and now
  and then ran past its 120 s limit and failed main. The CI Valgrind runtime
  suite, `make test-valgrind`, `make valgrind-check` and the contrib Valgrind
  gate take the flag too.
