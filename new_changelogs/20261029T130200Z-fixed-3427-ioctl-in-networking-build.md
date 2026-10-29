- **The embedded build compiles the HTTP server's stubs again.**
  `std/net/aether_http_server.c` included `<sys/ioctl.h>`, for the FIONREAD
  check of #3405, where every POSIX build reads it, and a bare-metal target
  has none. It is now included with the file's other socket headers, in the
  part a build with networking compiles (#3427).
