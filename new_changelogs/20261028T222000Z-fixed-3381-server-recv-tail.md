- **The pure TLS server's reads no longer drop the end of a record
  (#3381).** `std.cryptography.tls13_server`'s recv for `std.http` copied
  as much of a decrypted record as the caller's buffer took and freed the
  rest. The HTTP server reads with 16383 bytes of room, and its
  Content-Length loop asks for just what a body still lacks, so a record of
  16384 bytes lost a byte and a request body over 16 KiB never completed
  (the request hung until its timeout). What does not fit is now kept for
  the next read, as the pure client's bridge already did.
