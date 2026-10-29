- **A certificate whose keyUsage does not allow signing is no longer
  accepted as a TLS peer (#3309).** `tls13_cert.validate_chain`, and so the
  pure TLS client, took any leaf for `PURPOSE_SERVER` or `PURPOSE_CLIENT`
  whatever its keyUsage said, a CA certificate with keyCertSign and cRLSign
  only among them. TLS 1.3 signs the CertificateVerify with the leaf's key,
  and RFC 8446 4.4.2.2 requires digitalSignature when keyUsage is present;
  OpenSSL refuses such a leaf as an unsuitable purpose, so the two backends
  disagreed. The leaf's keyUsage, when present, must now allow
  digitalSignature.
