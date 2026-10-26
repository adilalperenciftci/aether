- **The rate limiter and the ip_hash balancer know a client by its peer, not
  a header it sends.** `middleware.use_rate_limit` keyed its token bucket on
  `X-Forwarded-For`, then `X-Real-IP`, so a client that sent a fresh
  `X-Forwarded-For` on every request got a fresh bucket and was never
  limited; the proxy's `ip_hash` balancer let a client pick its upstream the
  same way. Both key on `http.request_remote_addr` now: the connection's
  peer, or, behind `middleware.use_real_ip`, the client it resolved (#3173).
