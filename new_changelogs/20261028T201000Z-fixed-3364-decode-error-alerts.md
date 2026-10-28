- **The pure TLS client sends decode_error for a repeated EncryptedExtensions
  extension and a nonzero compression method (#3364).**
  `std.cryptography.tls13_hs.check_extensions` judged each extension as it
  came, so an extension the server sent twice was refused as unsolicited
  (unsupported_extension) before the repeat was seen. The block is now
  checked whole first: a repeated type is decode_error in
  EncryptedExtensions and illegal_parameter in the other messages, as
  BoringSSL sends them. A ServerHello or HelloRetryRequest whose
  legacy_compression_method is not 0 is decode_error instead of
  illegal_parameter (RFC 8446 4.1.3).
