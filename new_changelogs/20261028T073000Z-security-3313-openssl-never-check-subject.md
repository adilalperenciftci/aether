- **The OpenSSL TLS backend matches the host against subjectAltName only
  (#3313).** `std.http`'s OpenSSL client (and the wss:// client) let
  OpenSSL fall back to the subject common name when a certificate had no
  DNS subjectAltName, which the pure-Aether backend never does (RFC 9525,
  as browsers): a CN-only certificate was accepted on one backend and
  refused on the other. Both clients now set
  X509_CHECK_FLAG_NEVER_CHECK_SUBJECT.
- **Migrating:** a server certificate that names its host only in the
  subject CN no longer verifies on the OpenSSL backend; reissue it with the
  name in subjectAltName.
