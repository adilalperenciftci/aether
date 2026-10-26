- **`spawn_sandboxed`'s children call only async-signal-safe functions.**
  The child set `LD_PRELOAD` and the grant source with `setenv`, ran the
  program with `execlp` and printed with `perror` between fork and exec,
  which a child of a threaded parent may not do. The parent now builds the
  env, resolves the program on `PATH` and makes both argvs, the child
  calls `execve`, and the parent prints why a child could not run its
  program (#3200).
