- **A keep-alive connection on the pure TLS server no longer stalls on a
  request it already holds, nor reads TLS records as HTTP (#3384).**
  `std.http` decides whether the next request is there before it parks a
  connection, and asks OpenSSL with `SSL_pending`; the pure server's
  buffered plaintext (the kept tail of a record, #3381) and the whole
  records it had already read were invisible, so a pipelined request in
  the record that ended a body waited for the idle timeout. On Linux and
  macOS the same check read the socket directly for any connection without
  OpenSSL, the pure TLS ones included, taking the client's next TLS record
  as plaintext. New `aether_pure_tls_server_pending` callback, checked
  where `SSL_pending` is (also for WebSocket readiness), and the direct
  read is for plain connections only.
