- **The pure TLS client's alert reaches the server when a handshake fails
  (#3368).** After refusing a server's message, `std.cryptography.tls13_client`
  sent its alert and closed the socket with the rest of the server's flight
  still unread. Closing a socket that holds unread bytes sends a TCP reset,
  and a peer that gets one before reading (Windows does this) drops the
  alert, so the server never learned why. The client now reads and drops
  what has already arrived (at most 256 KiB, waiting at most 5 ms for each
  more) before it closes.
