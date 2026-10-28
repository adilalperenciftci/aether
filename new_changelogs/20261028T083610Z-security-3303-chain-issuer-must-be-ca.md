- **The pure-Aether TLS client no longer accepts a certificate signed by a
  non-CA.** `std.cryptography.tls13_cert`'s `chain_verify_path` checked only
  names and signatures at each hop, so any leaf certificate a trusted CA had
  issued could sign a certificate for any host and the client accepted it. An
  issuing certificate must now carry basicConstraints `cA=TRUE` and, when it has
  a keyUsage extension, `keyCertSign`. `leaf_is_ca` and `leaf_key_cert_sign`
  report both. The rest of RFC 5280 path validation listed in #3303
  (pathLenConstraint, extendedKeyUsage, critical extensions, name constraints,
  intermediate validity, backtracking) is still open. The OpenSSL backend was
  not affected. Contributed by Adil Alperen Çiftci (#3340).
