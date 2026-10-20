- **Every pipe the runtime makes closes on exec.** The scheduler's I/O
  poller (the poll() backend), std.net's event loop, HTTP server and
  `net.pipe_open`, and std.http's HTTP/2 sessions made their wake pipes with
  a plain `pipe()`, so every child a program started kept them open across
  exec (the HTTP server set the flag afterwards, outside the fork lock
  macOS needs). They are made close-on-exec now, by the same helper
  std.os's process calls and contrib/host's bridges use, which moved from
  std/os into the runtime (`runtime/utils/aether_spawn.h`,
  `aether_pipe_cloexec` and `aether_fork`), with the one fork lock of the
  process beside it (#3046).
