- **The pure TLS server keeps its private key shielded.** The key a server
  loads once and keeps for its life (#3362) is now held by
  `std.cryptography.shield`, sealed behind a 16 KiB random pre-key, and in
  the clear only for each signature; a key whose sealed form changed in
  memory is refused, and the handshake ends with `internal_error`. An RSA
  key is shielded as its PKCS#1 DER and rebuilt for each signature. For
  code that read `tls13_server.ServerKey`'s fields: `secret` and `rsa` are
  gone, and `shielded` holds the shield handle; `load_private_key`,
  `free_private_key` and `accept` are unchanged (#3376).
