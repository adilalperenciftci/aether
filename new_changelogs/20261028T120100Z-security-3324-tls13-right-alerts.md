- **The pure TLS stack checks each handshake message to its last byte and
  sends the alert RFC 8446 names (#3324).** The client took a server
  flight with messages out of their place (a NewSessionTicket or an unknown
  message among them, no CertificateVerify), bytes after a CertificateVerify's
  signature, a Finished longer than the hash, and a CertificateRequest with a
  request context or without signature_algorithms; it now refuses each with
  unexpected_message, decode_error or missing_extension. A CertificateVerify
  with a scheme the client did not offer, or one that does not fit the
  certificate's key, is illegal_parameter, and a signature that does not
  verify decrypt_error, also when a resumption's Finished does not match.
  The server read the client Finished with no alert at all; it now answers,
  under its application keys, bad_record_mac, unexpected_message,
  decode_error or decrypt_error.
