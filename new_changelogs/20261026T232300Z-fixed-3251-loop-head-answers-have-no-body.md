- **A HEAD the proxy answers itself has no body on the event loop either.**
  On Linux and macOS the proxy event loop wrote the responses the proxy made
  without an upstream's answer (a 502 for an upstream it cannot reach or an
  upgrade it does not forward, 503 no_upstream, the 504 for a timeout, a
  cache hit) with their bodies to a HEAD request, which a client reads as the
  start of the next response. They now go out as the worker path writes
  every response, the head only for HEAD (#3251).
