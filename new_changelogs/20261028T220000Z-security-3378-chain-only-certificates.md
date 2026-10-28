- **The pure TLS server never sends a non-certificate PEM block as part of
  its chain (#3378).** `std.cryptography.tls13_server.parse_cert_chain_pem`
  split the certificate text at each END CERTIFICATE line and decoded the
  first PEM block of each piece, whatever its label. A private key between
  two certificates (or a combined key-and-certificate file) went into the
  chain, and the server sent the key's PKCS#8 DER to every client as a
  CertificateEntry; `server_set_tls` checked only the leaf, so it accepted
  the files. Only `BEGIN CERTIFICATE` blocks now form the chain, every other
  block is skipped as OpenSSL skips it, and every entry is parsed as a
  certificate when the chain is loaded: a certificate block that does not
  decode or parse refuses the whole text, and `server_set_tls` says which.
  New `tls13_server.parse_cert_chain_pem_checked`.
