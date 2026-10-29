- **`bytes.wipe` and `bytes.wipe_free`: zeroing a secret that the compiler
  cannot drop.** A buffer that held key material, a nonce or the text of a
  private key was zeroed with a loop of `bytes.set` calls before it was
  freed, a dead store the C compiler may remove once it inlines the calls,
  and only up to the buffer's length. `bytes.wipe(b)` zeroes the whole
  capacity through a call the compiler cannot see through (OpenSSL's
  `OPENSSL_cleanse` technique), and keeps the buffer; `bytes.wipe_free(b)`
  wipes, then frees. The cryptography modules' private wipe helpers and the
  HTTP server's copies of the TLS key text use it (#3376).
