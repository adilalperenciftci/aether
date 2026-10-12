- **HTTPS on Windows trusts the system certificate store, and both TLS stacks
  agree on what they trust.** Neither `std.http.client` over OpenSSL nor the
  pure-Aether `std.cryptography.tls13_client` read the Windows store, so a
  program copied to a machine without MSYS2 or Git for Windows could make no
  HTTPS request, and the two looked for different bundle files, so one could
  work where the other failed. Both now trust, unless `SSL_CERT_FILE` or
  `SSL_CERT_DIR` is set, every certificate of the ROOT system store together
  with the first bundle of one shared list: the bundle the release ships
  beside the program, MSYS2's MINGW64 and UCRT64 bundles, then Git for
  Windows'. An `SSL_CERT_FILE` that cannot be read now fails closed on the
  OpenSSL stack too, as it did on the pure one, instead of falling back to
  the bundle files (#2675).
