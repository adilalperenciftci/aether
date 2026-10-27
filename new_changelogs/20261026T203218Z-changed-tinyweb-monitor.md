- **TinyWeb servers take a `std.http` monitor (#3131).**
  `tinyweb.http_server(server)` returns the `std.http` server behind a TinyWeb
  server, so `http.monitor(tinyweb.http_server(server)) { listening() … }`
  attaches before `tw_start`, as it does for a `std.http` server, and
  `http.null_monitor` silences the console banner. The server is made on first
  use and freed by `tw_stop`; starting again makes a fresh one, which takes its
  own monitor. A failed bind
  now returns `std.http`'s reason unchanged (`cannot bind 127.0.0.1:8080:
  Address already in use`) instead of naming the address twice. `example_app`
  prints its curl hints from `listening`, with the bound port, where it used to
  print them only after the server had stopped.
