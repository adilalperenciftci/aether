- **`make compiler-fast` links.** Its monolithic build listed the runtime
  pieces aetherc needs on its own and had lost `aether_spawn.c` and
  `aether_sandbox.c`, so it failed at the link; it also did not wait for the
  generated headers. It now uses the same source list and headers as the
  regular aetherc rule (#3351).
