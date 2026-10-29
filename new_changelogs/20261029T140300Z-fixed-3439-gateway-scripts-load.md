- **Gateway script libraries load again on Linux and macOS.** Every
  `--emit=lib` library's C carried a table of the host API (deadline, memory
  cap, caller, accounts), which made a script built to bind to its host's
  runtime reference objects the host never linked: "undefined symbol:
  aether_set_memory_cap". The runtime keeps the table itself, in
  `aether_exec.c`, which every library with a runtime of its own links; a
  program that loads libraries (`std.dl`) keeps what every Aether library
  binds to; and the cooperative runtime list has `libaether_caps.c`, which a
  wasm library's host API needs (#3439).
