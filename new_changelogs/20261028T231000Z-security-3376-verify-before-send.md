- **The pure TLS server checks every signature before it sends it.** A
  CertificateVerify signature computed wrongly, by a fault in the
  arithmetic or a bit flipped in memory (a glitch, Rowhammer), can disclose
  the private key: one faulty RSA-CRT signature factors the modulus, and
  two signatures of one message under a deterministic nonce (RFC 6979
  ECDSA, Ed25519) give the key. Each signature is now verified against the
  certificate's key, the one the client checks, before it is sent; one
  that does not verify is wiped and never sent, and the handshake ends with
  `internal_error`. On by default, for every scheme the server signs
  (ECDSA P-256, P-384, P-521, rsa_pss_rsae_sha256/384/512, Ed25519). The
  cost is one verification per handshake: about as much as the signature
  for ECDSA and Ed25519, about a tenth of it for RSA. New in
  `std.cryptography.tls13_cert`: `leaf_signature_holds` and
  `verify_cert_verify_rsa_pss_scheme` (#3376).
