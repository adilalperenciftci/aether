- **Pure TLS server connections close their descriptor exactly once (#3138).**
  The TLS bridge owns each accepted descriptor on success and failure; HTTP
  teardown no longer closes the same number again after another worker may
  have reused it. Refused handshakes also release their socket wrapper, and
  `tcp.close` releases the descriptor even after a peer EOF or receive error.
