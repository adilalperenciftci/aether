- **contrib's process hosts prepare their child in the parent.**
  `contrib.host.aether` and `contrib.host.go` set `LD_PRELOAD`, the grant
  source and the map with `setenv` in the forked child, and the Go host
  ran the program with `execvp` there, which a child of a threaded parent
  may not do. The parent now builds the env (and for the Go host looks the
  program up on `PATH`), and the child only calls `execve` (#3200).
