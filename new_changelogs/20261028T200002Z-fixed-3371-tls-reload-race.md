- **Re-loading a running server's TLS is safe.** `server_set_tls` on a
  server that was already accepting freed the old OpenSSL context without a
  lock, and both accept paths read the pointer and then called `SSL_new` on
  it, so a connection accepted in between used freed memory. The TLS state is
  swapped under a lock now, and each accept takes a reference to what it
  uses (the `SSL_CTX`, or the pure server's credentials), so what a re-load
  replaces is freed by its last user. Two re-loads at once, from two
  threads, are safe too: the configuration calls take turns (#3371).
