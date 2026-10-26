- **The access log and metrics see every response.** A response a
  middleware answered (a proxied request, a 401 from basic auth, a 429 from
  the rate limiter) went past the request hooks, on HTTP/1.1 and HTTP/2
  alike, so a gateway's access log had no line for its proxied requests. The
  hooks now observe every response; transformers stay the route handler's,
  as documented. The proxy event loop serves a connection only when the
  server has no hook either, as it ran none (#3213).
