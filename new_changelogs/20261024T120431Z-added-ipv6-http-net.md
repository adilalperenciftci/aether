- **std.http, std.net and TinyWeb speak IPv6.** A server binds an IPv6
  address (`"::1"`), or `"::"` for every interface of both families, so
  `web_server_host("::", 8443)` serves IPv4 and IPv6 clients from one socket
  and reports an IPv4 client as `127.0.0.1`, not `::ffff:127.0.0.1`. Names
  bind as before: `"localhost"` still listens on 127.0.0.1 only. The client
  takes bracketed URLs (`https://[2001:db8::1]:8443/x`), resolves a name to
  every address it has and dials them Happy-Eyeballs style: a 250 ms first
  try on each but the last, a second try for any that only timed out, and
  the family that connected remembered per host and port and tried first
  next time (so `localhost` -> ::1 against a server on 127.0.0.1 costs one
  short try, not Windows' two-second refused SYN on every connection). It
  writes the brackets back into `Host:`, the
  `CONNECT` line and a proxied request line. `net.tcp_connect_raw`,
  `net.tcp_listen_on_raw` (`"::1"`, `"[::1]"`, `"::"`) and the WebSocket
  dial do the same. A `tcp` sandbox grant names an IPv6 host as
  `"[::1]:8443"`, or `"[::1]"` for any port, and a grant for one family
  never admits the other. Every listener, dial and resolver now goes through
  one header, `std/net/aether_net_addr.h`.
