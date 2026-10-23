- **The actor scheduler counts and places its threads by the CPUs the
  process may use.** Thread i was bound to CPU i (Linux) or given it as its
  ideal processor (Windows), a number from 0: under `taskset -c 4-7` the
  threads left the CPUs the program was started on, and in a cpuset
  container a binding outside the set was refused. They now go to the
  i-th CPU of the process's affinity mask. The thread count was the
  machine's (16 threads for a 2-CPU container); it is now no more than
  the affinity mask and a cgroup CPU quota allow, as `std.worker` and the
  HTTP server already sized their pools. Linux keeps the hard binding,
  measured under background load (#3089, #3106).
