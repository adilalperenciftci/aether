- **The proxy event loop does not pool an upstream connection that said it
  closes.** On Linux and macOS the loop put an upstream connection back in
  the client pool after a response with `Connection: close`, or an HTTP/1.0
  one without keep-alive, so the next request to that upstream took a
  connection the upstream had closed. It now decides as the worker path's
  client does, by one shared rule (#3259).
