- **Choose the TLS backend per HTTPS request and per server (#1298).**
  `client.set_tls_backend(req, "aether" | "openssl" | "")` and
  `http.server_set_tls_backend(server, ...)` pick the pure-Aether TLS 1.3
  stack or OpenSSL explicitly; `""` keeps the default, which is unchanged:
  OpenSSL where it is built in, the pure stack where it is not, and
  `AETHER_PURE_TLS=1` to move a whole process. An explicit choice wins over
  the variable, and pooled client connections are kept apart per backend.
  Both return an error string, before any network is touched, when the
  backend cannot be used: `"openssl"` in a build without OpenSSL, `"aether"`
  in a program that does not import `std.cryptography.tls13_client` (or
  `tls13_server`), or an unknown name. `server_set_tls_backend` may come
  before or after `server_set_tls`. `tests/integration/https_tls_backend_select`
  runs every client backend against every server backend and checks which
  one ran from each side's TLS 1.2 peer.
