- **The pure TLS client gets session tickets from Go and BoringSSL servers
  (#3363).** Its full-handshake ClientHello carried no
  psk_key_exchange_modes, and a server may resume only with a mode the
  client lists (RFC 8446 4.2.9), so Go's and BoringSSL's servers sent it no
  NewSessionTicket and `conn_get_ticket` had nothing to return.
  `tls13_hs.client_hello_full` now offers { psk_dhe_ke }.
