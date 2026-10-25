- **std is silent: the HTTP server reports through return values and a
  monitor, never by printing (#3131).** A failed bind or start used to print
  its reason to stderr while `server_bind` returned `"bind failed"`; the reason
  is now the error (`"cannot bind 0.0.0.0:8080: Address already in use"`), and
  `http_server_error(server)` reads it after a raw call. The "Server running at
  …" banner comes from a monitor: `http.monitor(srv) { listening() |host,
  port| { … } stopped() |host, port| { … } }` registers closures the server
  calls, and `http.console_monitor` / `http.null_monitor` are the stock ones.
  `http.server_start` uses the console monitor when the program chose none, so
  `ae run server.ae` still shows the banner; `server_start_background` and the
  raw `http_server_start_raw` print nothing unless given one. `worker.wait()`
  returns `(int, string)` with the reason it refused, instead of printing it.
  `make check-docs` runs `check_std_silent.py`, which fails on a write to
  stdout or stderr from std's C; an exempt one (a requested report, the last
  line before an abort) carries `silent-ok: <why>`. The rule is in
  `docs/stdlib-module-pattern.md`.
