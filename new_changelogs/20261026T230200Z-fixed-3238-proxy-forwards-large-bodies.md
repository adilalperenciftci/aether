- **std.http.proxy forwards a request body over 16 KiB.** The server streams
  a body larger than its connection buffer, and the proxy forwarded only what
  was buffered, which for a streamed body is nothing: the upstream got the
  client's Content-Length and no bytes, waited, and the client got 504 when
  the proxy gave up. Every proxied upload over 16 KiB failed that way on
  Windows, and on Linux and macOS on a gateway the event loop does not
  serve. The proxy now reads a streamed body, up to its body cap, before
  forwarding it, and refuses with 400 one that ends short of its
  Content-Length (#3238).
