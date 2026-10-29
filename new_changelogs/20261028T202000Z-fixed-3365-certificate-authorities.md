- **The pure TLS client checks a CertificateRequest's certificate_authorities
  (#3365).** `std.cryptography.tls13_hs.check_certificate_request` ignored
  the extensions' bodies, so the client answered a CertificateRequest whose
  certificate_authorities was an empty list or carried bytes after its
  names. Such a list, an empty name in it, and a signature_algorithms or
  signature_algorithms_cert list that is empty, odd or does not fill its
  extension are now refused with decode_error (RFC 8446 4.2.4, 4.2.3).
