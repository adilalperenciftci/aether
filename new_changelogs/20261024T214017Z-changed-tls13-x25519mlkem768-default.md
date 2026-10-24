- **The pure TLS client offers X25519MLKEM768 by default, and the pure server
  accepts it (#2483).** Every ClientHello from `std.cryptography.tls13_client`
  now carries an X25519MLKEM768 key share (the post-quantum hybrid, RFC 10024)
  beside the x25519 and secp256r1 ones, so `connect()`, `connect_mtls()` and
  the `std.http.client` fallback in builds without OpenSSL get post-quantum key
  exchange from any server that supports it. The ClientHello grows by about
  1.2 KB. `connect_pq()` is now `connect()` with a fresh scalar, and the new
  `conn_group(conn)` reports the group the server chose. The pure server
  (`std.cryptography.tls13_server`, used by `AETHER_PURE_TLS=1`) prefers the
  hybrid when a client offers it. It answers a share that fails the FIPS 203
  §7.2 check, or has the wrong length, with a fatal `illegal_parameter` alert,
  and now sends an alert for any refused ClientHello instead of dropping the
  connection. A HelloRetryRequest now ends the handshake: the client already
  sends a share for every group it supports, so any retry the server asks for
  is one RFC 8446 §4.1.4 says to abort on.
