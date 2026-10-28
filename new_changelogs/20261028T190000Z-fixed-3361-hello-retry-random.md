- **The pure TLS stack knows a HelloRetryRequest when it sees one (#3361).**
  `std.cryptography.tls13_hs` compared a ServerHello's random against a
  mistyped copy of RFC 8446's HelloRetryRequest value (the second half was
  wrong), so the client read a real server's HelloRetryRequest as a broken
  ServerHello ("bad key_share") and real clients refused the pure server's.
  The value is now computed as the RFC defines it, SHA-256 of
  "HelloRetryRequest", and checked against the RFC's bytes; the client
  follows `openssl s_server -groups P-256`'s HelloRetryRequest on a
  resumption, and `openssl s_client` completes the pure server's.
