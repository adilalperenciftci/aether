- **contrib/host's bridges spawn children by std.os's rules.**
  `contrib.host.aether` made its capture pipe with a plain `pipe()`, so a
  child another thread started while a capture was open inherited the
  write end and the capture waited for that child to exit, the #2917 stall
  in a second place; it and `contrib.host.go` also forked outside the fork
  lock that keeps a fork away from a half-made pipe where `pipe2` is
  missing (macOS, #3028). std.os now exports its close-on-exec pipe and
  its fork as `aether_os_pipe_cloexec` and `aether_os_fork`
  (`std/os/aether_os.h`), and both bridges use them (#3040).
