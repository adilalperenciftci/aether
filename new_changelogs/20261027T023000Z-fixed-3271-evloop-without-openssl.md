- **The proxy event loop builds warning-free without OpenSSL.** Its TLS
  client write was defined in every build and called only from the TLS
  branch, so a build without OpenSSL, which every `--target=` cross build
  is, failed under `-Werror` with an unused function. It is defined only
  where TLS is (#3271).
