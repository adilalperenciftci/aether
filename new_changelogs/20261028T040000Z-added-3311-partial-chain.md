- **`client.set_partial_chain(req, 1)` trusts an intermediate CA on its
  own.** Since #3310 a trust anchor must be a self-signed root on both TLS
  backends, as on OpenSSL by default, so a CA file holding an intermediate
  CA alone (a private PKI that hands out its issuing CA, or pinning one CA
  below a public root) no longer anchors a path on the pure-Aether backend.
  `set_partial_chain` is the explicit way to trust one, the same on both
  backends (OpenSSL's `X509_V_FLAG_PARTIAL_CHAIN`, the pure client's
  `tls13_cert.TRUST_PARTIAL_CHAIN`): any certificate in the trust store ends
  a path, a trusted certificate that is not a root must still be a CA, and
  peer and hostname verification stay on. Off by default; pooled connections
  are kept apart by it (#3311).
