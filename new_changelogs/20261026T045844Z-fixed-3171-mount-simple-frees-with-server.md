- **`proxy.mount_simple` no longer leaks its options and pool.** It built a
  pool and an options block holding the pool's last reference, and handed
  the block to the server as its middleware's user data, which
  `http_server_free` never released: about 600 bytes per mount. A
  middleware can now own its user data (`http_server_use_middleware_owned`,
  a release hook `http_server_free` runs), and `mount_simple` gives its
  block to the server.
  `proxy.mount`, `mount_methods` and `mount_match` say who frees the options
  they take: the caller, after the server (#3171).
