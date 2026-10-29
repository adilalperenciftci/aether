- **The pure TLS stack's fatal alert is no longer lost to a TCP reset when
  a connection fails after the handshake.** The close after a failure
  closed the socket with what the peer had sent after (the rest of a record
  too long to read) still unread, which ends with a reset, and a peer that
  got the reset before it read could discard the alert: it saw a bare
  close. The client and the server now drain the socket before that close,
  as a failed handshake's close on the client already did (#3368), with
  `tcp.close_drained(sock)` in std.tcp; the server's library entry for a
  failed handshake drains too (#3465).
