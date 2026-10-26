- **Middleware before std.http.proxy runs on every proxied request.** On
  Linux and macOS a server that mounted a proxy handed its connections to
  the proxy event loop, which ran the proxy exchange alone: basic auth, the
  rate limiter, CORS and `use_real_ip` registered ahead of the proxy were
  skipped for every request the proxy forwarded. The loop now serves a
  connection only when the proxy is the chain's first middleware, and its
  requests carry their connection's peer (the proxy's X-Forwarded-For had
  named the hop "unknown") (#3203).
