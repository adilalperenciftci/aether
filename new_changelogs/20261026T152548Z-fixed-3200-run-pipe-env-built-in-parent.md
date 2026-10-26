- **`os.run_pipe`'s child gets its `AETHER_IPC_FD` without a `setenv`
  between fork and exec.** The child set it there, and `setenv` mallocs and
  takes the environment's lock, which a thread of the parent may have held
  at the fork: the child could hang before it ran the program. The parent
  now builds the child's env, this process's environment without an
  `AETHER_IPC_FD` of its own plus `AETHER_IPC_FD=3` (#3200).
