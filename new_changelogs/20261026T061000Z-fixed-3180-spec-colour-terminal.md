- **std.spec colours its output only for a terminal.** Every ✓/✗ line and
  the summary were wrapped in ANSI escapes wherever they went, into a pipe,
  a file or a CI log, and with `NO_COLOR` set, so a suite's output could
  not be compared or read plainly. The colour is now decided once, in one
  place every escape goes through: never with `NO_COLOR` set, always with
  `FORCE_COLOR` set (`NO_COLOR` wins), otherwise when stdout is a terminal.
  `io.is_terminal(fd)` is new in std.io for the same test in any program
  (a console on Windows, where a console stream also gets virtual terminal
  processing so the escapes render) (#3180).
