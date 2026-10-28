- **The pure TLS client and server do HelloRetryRequest (#3325).** The
  client gave up at any HelloRetryRequest and the server refused a
  ClientHello whose key shares held no group it takes. The client now
  follows one that asks for a cookie or, on a resumption, for a secp256r1
  share (its first ClientHello there carries x25519's only): the
  change_cipher_spec, then the same ClientHello with the cookie and the
  share, without early data and with its PSK binder computed again, in a
  record of version 0x0303, under the message_hash transcript (RFC 8446
  4.1.4, 4.4.1). It refuses one naming a group it already has a share for
  or never offered, one asking for no change (illegal_parameter), an empty
  cookie (decode_error), a second one (unexpected_message), and a
  ServerHello after it with another cipher suite or group. The server asks
  for X25519MLKEM768 or X25519 when `supported_groups` names it but no share
  is for it (4.2.8), sends its compatibility change_cipher_spec after the
  HelloRetryRequest, and refuses a second ClientHello without that share,
  with another session id or suite, or with early data (illegal_parameter).
  New `tls13_hs.hello_retry_request(session_id, cipher_suite, group)` and
  `tls13_hs.client_hello_retry(ch1, group, share, cookie, out)`.
