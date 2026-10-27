- **A proxy gateway on pure-Aether TLS is served on the worker path.** On
  Linux and macOS the proxy event loop took the connections of a gateway that
  terminates TLS with the pure-Aether stack (`AETHER_PURE_TLS=1`, or a build
  without OpenSSL), though its TLS is OpenSSL's: it closed every connection,
  or in a build without OpenSSL read the TLS bytes as HTTP. Such a gateway now
  keeps the worker path, which runs the pure stack (#3256).
