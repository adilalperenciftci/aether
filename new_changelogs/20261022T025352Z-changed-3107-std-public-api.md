- **std's TLS modules, the HTTP load balancer and tinyweb's tests call other
  modules through their public functions.** They called the `*_raw` C
  bindings of std.net, std.fs and std.http directly. The TLS modules now
  dial with `tcp.connect`, read with `tcp.read_n`, and load certificates,
  keys and trust stores with `fs.read` and `fs.list_dir`. `fs.read` opens in
  binary mode, so on Windows a certificate file is no longer read through
  text mode, and a trust store that cannot be opened names the OS reason.
  The load balancer starts with `http.server_start` and `server_set_tls`.
  tinyweb's tests and schema showcase use std.http.client, which gives the
  status and the body (#3107).
