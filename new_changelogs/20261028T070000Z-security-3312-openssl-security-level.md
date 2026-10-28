- **The OpenSSL TLS backend refuses RSA keys under 2048 bits everywhere
  (#3312).** `std.http`'s client and server contexts ran at the security
  level the system configured: OpenSSL's own default, level 1, accepts a
  1024-bit RSA certificate, which the pure-Aether backend refuses, so the
  same program accepted a different set of servers depending on the backend
  and the distribution. Every OpenSSL client and server context now runs at
  level 2 at least (RSA, DSA and DH of 2048 bits or more, elliptic curves of
  224 bits or more); a system configured higher stays higher.
- **Migrating:** a server certificate with an RSA key under 2048 bits, or a
  chain with one, no longer verifies on the OpenSSL backend, and
  `http.server_set_tls` refuses to load one; reissue it with a 2048-bit (or
  larger) RSA key or an EC key.
