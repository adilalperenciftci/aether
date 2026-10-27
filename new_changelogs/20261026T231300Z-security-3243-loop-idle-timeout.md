- **The proxy event loop closes a quiet client's connection.** On Linux and
  macOS the proxy event loop had no timeout on its clients: a connection that
  sent nothing, before its first request, between requests or partway
  through one or through a TLS handshake, was held for as long as the client
  kept it open, so a client could hold as many descriptors and buffers as the
  server would take. The loop now closes it after the server's keep-alive
  idle timeout (30 seconds unless set), as the worker path's receive timeout
  does (#3243).
