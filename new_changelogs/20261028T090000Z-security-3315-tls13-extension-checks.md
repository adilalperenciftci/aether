- **The pure TLS client refuses extensions it never asked for (#3315).**
  `std.cryptography.tls13_client` accepted any extension in a ServerHello
  or EncryptedExtensions: unknown types, TLS 1.2 ones
  (extended_master_secret, renegotiation_info, ec_point_formats), a
  key_share or supported_versions out of place, a pre_shared_key in a full
  handshake, duplicates, an ALPN protocol it did not offer, and an
  EncryptedExtensions with no extensions block at all. RFC 8446 4.2 requires
  refusing them; now the client does, with unsupported_extension for what it
  never offered, illegal_parameter for an offered extension out of place or
  repeated, and decode_error for a block that does not parse, and it sends
  that alert. New `tls13_hs.check_extensions(kind, exts, offered)` holds the
  rules.
