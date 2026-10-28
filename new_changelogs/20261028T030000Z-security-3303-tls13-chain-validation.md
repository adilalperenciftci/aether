- **The pure TLS client validates the whole certificate path (#3303).**
  This extends #3340 by Adil Alperen Çiftci, which made every issuing
  certificate carry basicConstraints cA and, with a keyUsage, keyCertSign,
  read into `LeafCert.is_ca`, `has_key_usage` and `key_cert_sign`. The rest
  of RFC 5280 path validation that #3303 listed is here: pathLenConstraint,
  extendedKeyUsage, name constraints, critical extensions the client does
  not process, and the version and validity of everything above the leaf.
  New
  `tls13_cert.validate_chain(leaf, intermediates, anchors, at, purpose,
  max_depth)` checks all of these (RFC 5280 section 6 as the Web PKI
  profiles it), trying every candidate path with a bounded search, at `at`
  ("YYYYMMDDHHMMSS", "" for now), for `PURPOSE_SERVER` or `PURPOSE_CLIENT`,
  through at most `max_depth` intermediates that are not self-issued
  (negative for the default, 8); the client uses it, and
  `tls13_cert.chain_verify_path` now calls it for a server at the current
  time. #3340's decoders also stop reading three malformed encodings
  leniently: a keyUsage that is not a BIT STRING no longer counts as absent,
  a repeated extension no longer lets the last copy win, and a BOOLEAN other
  than 0x00 or 0xFF (a cA, or an extension's critical flag) is no longer
  read as TRUE; each makes the certificate refused.
  `tls13_cert.check_validity_at(c, at)` checks one certificate at a
  given time. A self-signed certificate pinned as its own anchor is trusted
  as it stands, whatever its basicConstraints say, as OpenSSL trusts it.
  `std/http/README.md` lists what the pure client validates.
