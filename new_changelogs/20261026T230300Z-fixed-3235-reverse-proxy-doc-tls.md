- **docs/http-reverse-proxy.md no longer says a TLS-terminating server
  leaves the proxy event loop.** The loop carries the client's TLS handshake
  and serves the connection through the session; the guide listed TLS among
  what keeps a thread per connection (#3235).
