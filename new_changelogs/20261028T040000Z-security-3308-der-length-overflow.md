- **A stapled OCSP response can no longer stop the pure TLS client
  (#3308).** `std.cryptography.tls13_cert`'s DER reader, under
  `parse_ocsp_status` and the OCSP signature check, read a length of four
  bytes into a 32-bit int: from 0x80000000 up it overflowed into a negative
  length that passed the bounds check, and the next read indexed before the
  buffer, a panic in the client on a response the server controls. Lengths
  of more than three bytes (16 MB) are refused now.
