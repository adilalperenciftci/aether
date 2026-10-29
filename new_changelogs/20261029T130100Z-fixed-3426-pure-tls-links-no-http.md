- **A program using the pure TLS stack without `std.http` links nothing of
  the HTTP server or client.** `std.cryptography.tls13_server` and
  `tls13_client` told `std.http` why a key or a handshake was refused
  through functions of the HTTP server and client, and the client read the
  Windows trust store through two more, so every such program pulled both
  out of libaether.a, and with the server the HTTP/2 code: on macOS, where
  Homebrew's nghttp2 makes that the real one, it did not link. The reason
  now goes through the callback registry (`aether_callback_set_reason`,
  `aether_callback_reason`, per thread), and the trust store has a file of
  its own, `std/net/aether_tls_trust.c`, which both HTTPS clients read
  (#3426).
