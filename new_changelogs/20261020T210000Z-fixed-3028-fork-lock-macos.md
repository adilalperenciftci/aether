- **On macOS, a capture's pipe no longer leaks into a child another thread
  starts.** #2917 made std.os pipes close-on-exec, atomically with `pipe2`
  where it exists; macOS has none, so a pipe was made close-on-exec in two
  steps, and a `fork` from another thread between them copied both ends into
  its child, so a short `os.run_full` capture waited for an unrelated long
  child to exit (`os_run_full_threads` caught one on CI). Without `pipe2`,
  pipe creation and `fork` now exclude each other through a read-write lock,
  as the Go runtime's ForkLock does (#3028).
