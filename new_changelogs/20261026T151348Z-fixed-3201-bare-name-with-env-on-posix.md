- **A bare program name is looked up on this process's `PATH` whatever
  `env` a spawn is given.** On POSIX the child looked the name up itself:
  with an explicit env, `os.run`, `os.run_capture`, `os.run_full` and
  `os.run_supervised` never found a bare name, and `os.spawn_proc` and
  `os.spawn_proc_to` ran it with this process's environment instead of the
  one given. The parent now resolves the program, as Windows does, and
  every child execs it with `execve` and its env, calling nothing between
  fork and exec that is not async-signal-safe (#3201).
