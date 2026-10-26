- **A Windows build without threads no longer warns about `<winsock2.h>`.**
  `aether_cpu_available.h` included the full `<windows.h>`, which brings the
  old `<winsock.h>`, so the HTTP server and its pool warned on every
  `-DAETHER_NO_THREADING` build and failed one with `-Werror`. It includes it
  lean, as `aether_thread.h` does (#3223).
