- **A program that panics links no sandbox.** Since a panic ends the
  sandbox levels pushed inside the frame it leaves (#2955), it called into
  `aether_sandbox.c` directly, and every program with a `panic` or a `try`
  linked the sandbox and its audit log (17 KB more for a small program on
  Windows MinGW). The sandbox now hands the panic its unwind through a
  pointer, set before any level can exist, so such a program links what it
  did before (`tests/integration/panic_link_surface` reads its symbol
  table).
