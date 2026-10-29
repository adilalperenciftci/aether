- **The pure TLS client verifies an Ed25519 server (#3335).** It offered
  ed25519 in signature_algorithms but had no Ed25519 branch where it checks
  the CertificateVerify, so a server with an Ed25519 certificate was refused
  with "unsupported CertificateVerify scheme". `tls13_cert.check_leaf_cert_verify`
  now verifies every scheme the client offers (ECDSA P-256, P-384, P-521,
  rsa_pss_rsae_sha256, Ed25519) with the certificate's own key.
