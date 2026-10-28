- **A short client Finished no longer crashes the pure TLS server (#3337).**
  The server compared the Finished's verify_data as the hash's length
  without checking the message held that much, so a client that sent a
  shorter one made the server process panic (a slice out of range), after
  the server's first flight and before any authentication. A longer one was
  taken (only the first bytes were compared) and one split over two records
  refused. The server now reassembles the client Finished across records,
  refuses verify_data of any other length with decode_error, and anything
  after it in its record with unexpected_message.
