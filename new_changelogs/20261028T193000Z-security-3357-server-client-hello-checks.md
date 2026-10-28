- **The pure TLS server checks the ClientHello and speaks the rest of
  TLS 1.3's baseline (#3357).** BoGo's server tests found it taking a
  ClientHello with compression methods other than null alone, a repeated
  extension, two key shares for one group, a server_name, key_share or
  certificate_authorities that does not parse, bytes after the extensions,
  and a pre_shared_key that is not the last extension; it now refuses each
  with illegal_parameter or decode_error (RFC 8446 4.1.2, 4.2), a
  ClientHello without supported_groups or key_share with missing_extension
  (9.2), and another handshake type with unexpected_message. It takes a
  secp256r1 key share, which 9.1 says a TLS 1.3 implementation MUST support,
  signs with rsa_pss_rsae_sha384 and rsa_pss_rsae_sha512 when the client
  offers only those (new `rsa.sign_pss_hash`, `rsa.verify_pss_hash` and
  `tls13_cert.sign_server_cert_verify_rsa_pss_scheme`), reads past 0-RTT
  data it does not take (4.2.10), and sends its compatibility
  change_cipher_spec whatever the client's session id. On both sides a
  Finished of the wrong length is now decrypt_error (4.4.4), and a
  protected record shorter than its tag bad_record_mac (5.2).
