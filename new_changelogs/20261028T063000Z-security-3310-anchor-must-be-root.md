- **On the pure TLS backend, as on OpenSSL's, only a self-signed root ends
  a certificate path (#3310).** `tls13_cert.validate_chain` let any trusted
  certificate end a path, an intermediate CA among them, and a self-issued
  root whose authorityKeyIdentifier names another key, issuer or serial.
  OpenSSL, without partial chains, ends a path only at a certificate that is
  self-signed by X509_check_akid's rule (issuer equal to subject, and an AKI,
  if any, naming the certificate itself), so the two backends accepted
  different chains. The pure backend applies the same rule now.
- **Migrating:** a CA file holding an intermediate rather than its root
  (`client.set_cafile`, `SSL_CERT_FILE`) no longer anchors a path on the
  pure backend, as it never did on OpenSSL; trust the root. Pinning an
  intermediate on both backends is #3311.
