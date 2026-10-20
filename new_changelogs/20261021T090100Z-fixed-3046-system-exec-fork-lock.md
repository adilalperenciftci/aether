- **`os.system` and `os.exec` start their shell through the runtime's
  locked fork.** In 0.836.0 they still used `system()` and `popen()`, which
  fork outside the fork lock, so on macOS a shell they started could
  inherit another thread's pipe between its `pipe()` and `fcntl()`. The
  exit status, signal handling and captured output are system()'s and
  popen()'s; a command that starts with `-` is run as a command, as glibc
  runs it (#3046).
