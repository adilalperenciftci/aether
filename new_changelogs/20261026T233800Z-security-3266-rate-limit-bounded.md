- **The rate limiter holds a bounded set of clients.** It kept a bucket for
  every client address it had ever seen, in 256 chains every request walked
  under one lock, so a client cycling addresses (one IPv6 client has more
  than enough) grew it, and slowed every request through it, without end.
  It now holds at most 16384 clients in 4096 chains, and at the bound the
  client seen least recently gives up its bucket (#3266).
