- **std.http, std.net and TinyWeb speak IPv6.** A server binds an IPv6
  address (`"::1"`), or `"::"` for every interface of both families, so
  `web_server_host("::", 8443)` serves IPv4 and IPv6 clients from one socket
  and reports an IPv4 client as `127.0.0.1`, not `::ffff:127.0.0.1`. Names
  bind as before: `"localhost"` still listens on 127.0.0.1 only. The client
  takes bracketed URLs (`https://[2001:db8::1]:8443/x`), resolves a name to
  every address it has and tries each in turn (the request's timeout is
  shared out among them), and writes the brackets back into `Host:`, the
  `CONNECT` line and a proxied request line. `net.tcp_connect_raw`,
  `net.tcp_listen_on_raw` (`"::1"`, `"[::1]"`, `"::"`) and the WebSocket
  dial do the same. A `tcp` sandbox grant names an IPv6 host as
  `"[::1]:8443"`, or `"[::1]"` for any port, and a grant for one family
  never admits the other. Every listener, dial and resolver now goes through
  one header, `std/net/aether_net_addr.h`.
