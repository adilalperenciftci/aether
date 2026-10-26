- **A program that cannot start never reads as exit 127 on POSIX.** exec
  fails in the forked child, so every `std.os` spawner saw only an exit of
  127 and no error, which a program that ran and exited 127 also gives.
  The child now writes its errno to a close-on-exec pipe before it exits,
  and each call reports the failure in its own shape, as Windows does:
  `os.run` and `os.system` return -1, `os.run_capture`, `os.run_full`,
  `os.spawn_proc`, `os.spawn_proc_to`, `os.run_pipe`,
  `os.run_pipe_drain_and_wait` and `os.run_supervised` return -1 with the
  reason (`"program not found"`, `"permission denied"`, `"not an
  executable"`), `os.exec` returns `"command failed"` and the raw capture
  null. `os.run_pipe` with an explicit env, which made the child exit 127
  without running the program, is refused with `"explicit env
  unsupported"` (#3170).
