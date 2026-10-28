- **The pure TLS client checks the ServerHello's fixed fields and its key
  share (#3318, #3353).** It took a ServerHello whose legacy_version is not
  0x0303, whose legacy_session_id_echo is not the session id it sent, whose
  extensions do not fill the message or whose key_share has bytes after the
  key, and on a resumption a selected_identity it never offered, a suite
  whose hash is not the ticket's, a ServerHello without key_share (an
  X25519 agreement over no share at all) and a key_share for a group it had
  no share for. Each is now refused, with illegal_parameter, decode_error
  or missing_extension (RFC 8446 4.1.3, 4.2.8, 4.2.11); an unoffered suite
  or group and a key share that is not a valid point, which got no alert at
  all, are illegal_parameter.
