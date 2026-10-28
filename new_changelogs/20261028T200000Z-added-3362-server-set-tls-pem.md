- **`http.server_set_tls_pem(server, cert_pem, key_pem)`: a TLS server from
  PEM text.** A program that held its certificate and key in memory had to
  write the key to disk for `server_set_tls`. The new call takes the text,
  with the same checks and results on both backends: OpenSSL loads it from
  memory, and the pure server parses the chain and key once, when the server
  is set up. The pure server used to read and parse both files on every
  connection; with either call it now parses once, and every connection
  shares the result. The server keeps its own copy of the text, for a later
  `server_set_tls_backend`, and wipes it when it is replaced or the server is
  freed. An encrypted key is refused at once: the OpenSSL backend used to ask
  for its passphrase on the terminal (#3362).
