- **A gateway keeps the proxy event loop with its middleware and hooks.** On
  Linux and macOS a server with `use_real_ip`, a rate limiter, CORS, an access
  log or metrics in front of a `std.http.proxy` mount served every connection
  from a thread of its own, because the event loop ran the proxy exchange
  alone (#3203, #3213). The loop now runs the middleware before the first
  mount and the request hooks itself, as the per-connection path does, when
  each is registered loop-safe: `use_real_ip`, `use_rate_limit`, `use_cors`,
  `use_vhost`, `use_rewrite`, the access log and metrics are, and
  `http.server_use_middleware_loop_safe` registers a program's own (from C,
  `http_server_use_request_hook_loop_safe` a hook). The auth middleware and
  `use_static_files` are not, and keep a server on a thread per connection,
  as does any middleware registered with `http.server_use_middleware`. A
  request the mount does not take goes on from the middleware after it, so a
  rate limiter counts it once. On the loop, a TLS connection's requests now
  say TLS, and a pipelined request with no body no longer took the next
  request as its body when it was forwarded upstream (#3214).
