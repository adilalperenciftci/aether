- **The pure TLS stack's record layer enforces RFC 8446 5 (#3317).** The
  client and the server read records of any type and length: a plaintext
  record over 2^14 bytes, a protected one over 2^14 + 256 or with an inner
  plaintext over 2^14 + 1 (padding included), a content type TLS 1.3 does
  not know, a change_cipher_spec after the handshake, more than one or of a
  value other than 1, an empty handshake record, a plaintext record inside
  the encrypted flight, and bytes after the server's Finished in its record
  (which crashed the client). An unlimited run of empty records cost the
  reader CPU without end; more than 32 in a row are now refused as a denial
  of service, as BoringSSL bounds them. Each is refused with
  record_overflow, unexpected_message or bad_record_mac, and the alert is
  sent. New `tls13_record.check_header` checks a record's header before its
  body is read; `OpenedRecord.alert` says what to send when a record does
  not open.
