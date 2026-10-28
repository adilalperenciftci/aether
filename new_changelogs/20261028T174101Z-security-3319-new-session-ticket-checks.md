- **The pure TLS client checks the NewSessionTickets it reads (#3319,
  #3354, #3356).** It took an empty ticket, a repeated early_data, an
  early_data that is not four bytes, empty TLS flags or flags ending in a
  zero byte, bytes after the extensions, and a ticket extension it knows
  that a ticket may not carry; it now refuses each with decode_error or
  illegal_parameter (RFC 8446 4.6.1, 4.2). It refused an extension it does
  not know, which 4.6.1 says to ignore, and now ignores it. A ticket may
  span records. `conn_get_ticket` dropped the application data that came
  before the ticket; it now keeps it for the next `conn_recv`, and a ticket
  `conn_recv` reads is kept for `conn_get_ticket`. A CertificateRequest
  after the handshake (no post-handshake authentication is offered) is
  unexpected_message.
