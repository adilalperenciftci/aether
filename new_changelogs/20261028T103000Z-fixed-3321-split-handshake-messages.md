- **The pure TLS stack reassembles a handshake message split across
  records (#3321).** RFC 8446 5.1 lets a peer split a handshake message over
  several records. The client read the ServerHello, and the server the
  ClientHello, from one record only, so a split one failed with "truncated
  header" or "length overruns buffer". Both now gather the fragments, and
  refuse with unexpected_message the bytes a peer puts after the message in
  its last record.
