- **A failed upstream dial no longer closes descriptor 0.** A fresh upstream
  connection started from descriptor 0, and a dial that failed before it made
  a socket (an upstream name that does not resolve) kept it, so on Linux and
  macOS the proxy event loop closed descriptor 0 when the client connection
  ended: the program's stdin, or whichever connection held 0 by then. It now
  starts from -1, no descriptor (#3248).
