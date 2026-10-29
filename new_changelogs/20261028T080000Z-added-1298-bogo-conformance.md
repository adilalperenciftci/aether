- **BoGo, BoringSSL's TLS test suite, runs against the pure TLS stack
  (#1298).** `make conformance-bogo` fetches BoringSSL at a pinned commit,
  builds its `ssl/test/runner` (Go 1.27) and drives
  `tests/conformance/bogo/shim.ae`, which runs `tls13_client` or
  `tls13_server` for each test; `config.json` disables each failing test
  with its reason. Not part of CI (it takes about five minutes).
  `make conformance-x509` runs x509-limbo and bettertls locally, as CI does.
- **Added:** `tls13_client.connect_socket(sock, host, cafile)` runs the
  verified handshake over an already-connected std.tcp socket.
