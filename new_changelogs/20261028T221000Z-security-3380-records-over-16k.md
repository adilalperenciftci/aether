- **The pure TLS server no longer dies on a certificate chain or a write
  over 16 KiB (#3380).** `std.cryptography.tls13_server` put each handshake
  message, and each `conn_send`, into one record. Over 2^14 bytes
  `seal_record` refuses, and the null went on to a slice that panicked
  outside any try, so a chain over 16 KiB killed an HTTP server on its first
  connection, and so did a response written in one piece over 16 KiB; the
  client's `conn_send` had the same fault. Handshake messages and data now
  go in as many records as they take (new `tls13_record.seal_records`, RFC
  8446 5.1), and every seal and send is checked on both sides: a record that
  cannot be sealed or sent ends that connection with an error, never the
  process.
