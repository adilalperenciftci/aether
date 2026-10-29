- **Shared-library capability checks now cover aliases and module families.**
  `--emit=lib` now applies the filesystem gate to `std.file` and `std.dir`,
  the network gate to `std.udp` and nested `std.http` modules, the OS gate to
  `std.dl`, and the extern gate to `contrib.host.*`.
