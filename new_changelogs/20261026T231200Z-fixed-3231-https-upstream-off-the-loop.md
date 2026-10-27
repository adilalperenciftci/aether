- **A proxy to an https upstream answers on Linux and macOS.** The proxy
  event loop dials plain HTTP only, yet it served a server whose proxy mount
  had an https upstream, and closed each client connection with nothing
  written. A mount with an https upstream is now served on the
  per-connection path, whose client speaks TLS, from the next request when
  one is added while the server runs, and a retry that reaches one hands its
  request there instead of dropping it (#3231).
