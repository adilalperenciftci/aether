- **A pure TLS connection's memory no longer grows with what it receives
  (#3379).** The record readers of `std.cryptography.tls13_server` and
  `tls13_client` appended every byte read and only moved an offset past the
  records they returned, so a connection kept everything it had ever
  received: a pure server reading a 200 MiB stream grew by 240 MiB, one
  long keep-alive connection could exhaust its memory, and the lengths would
  overflow at 2^31. The readers now drop what they have consumed before
  reading more, so a connection holds about one record and one read. Before
  the handshake, the server no longer reads past application_data records
  (empty ones cost nothing, so any number went by) except the refused 0-RTT
  data after a HelloRetryRequest, and the client takes one
  change_cipher_spec, of the byte 1, in its whole handshake (RFC 8446 5,
  D.4) instead of dropping any number of any content before the
  ServerHello; anything else is unexpected_message.
