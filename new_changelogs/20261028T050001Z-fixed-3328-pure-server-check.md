- **`server_set_tls` on the pure-Aether backend checks the certificate and
  key.** It returned "" without reading either file, so a missing file, an
  unusable or encrypted key, or a key belonging to another certificate made
  a server that started and then dropped every connection, with nothing
  logged. It now loads both, checks they are a pair (the key signs a test
  CertificateVerify the certificate's key verifies) and returns why it
  cannot serve them, as the OpenSSL backend does; a refused
  `server_set_tls_backend` keeps the server's earlier backend (#3328).
