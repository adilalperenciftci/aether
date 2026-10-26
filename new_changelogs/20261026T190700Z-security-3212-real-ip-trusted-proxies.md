- **`use_real_ip` names the client behind the proxies it trusts, and takes
  them as an argument: `middleware.use_real_ip(server, header, trusted)`.**
  It took the leftmost X-Forwarded-For entry from any peer, so a client that
  connects directly named itself any address, and behind a proxy that
  appends to the header (std.http.proxy, nginx by default, cloud load
  balancers) the entry it wrote was still the leftmost: a fresh rate-limit
  bucket per request, and any address to the handlers and the access log.
  The header is now believed only from a peer `trusted` names (addresses
  and networks, "127.0.0.1, 10.0.0.0/8, fd00::/8") and read from the right:
  the first entry that is not a trusted proxy is the client, as nginx's
  `set_real_ip_from` with `real_ip_recursive` has it. `"Forwarded"` reads
  each element's `for=`. Calls with two arguments no longer compile; give
  the proxies in front of the server (#3212).
