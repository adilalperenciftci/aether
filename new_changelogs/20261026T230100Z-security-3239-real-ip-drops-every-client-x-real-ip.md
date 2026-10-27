- **`use_real_ip` leaves none of the X-Real-IP headers a client sent.** It
  replaced the first with the client it resolved and kept any further one,
  so a client that sent the header twice had its second value forwarded by
  std.http.proxy, where an upstream that reads the last X-Real-IP took it
  (#3239).
