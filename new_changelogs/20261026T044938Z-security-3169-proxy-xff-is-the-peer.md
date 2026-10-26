- **std.http.proxy names the request's peer in X-Forwarded-For, and trusts no
  client's X-Real-IP.** The proxy appended `X-Forwarded-For: unknown` to
  every request that came without an `X-Real-IP` header, and took a
  client's own `X-Real-IP` as this hop's entry, so any client could write
  itself into the chain the upstream trusts. The entry is now
  `http.request_remote_addr`: the connection's peer, or, after
  `middleware.use_real_ip`, the client it resolved. `use_real_ip` makes that
  client the address the request reports (as nginx's realip does, the port
  reading 0) and replaces an `X-Real-IP` the client sent, which it used to
  keep (#3169).
