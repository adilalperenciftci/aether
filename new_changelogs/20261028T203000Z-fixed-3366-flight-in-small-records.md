- **The pure TLS client reads a server flight split into small records
  (#3366).** `std.cryptography.tls13_client` gave up on the server's
  encrypted flight after 256 records ("flight too long"), so a valid flight
  sent in one-byte records, which RFC 8446 5.1 allows, was refused. The
  bound is now on the flight's bytes (512 KiB) and on each message's
  length as soon as its header arrives (64 KiB, a Certificate 256 KiB),
  with unexpected_message past either.
