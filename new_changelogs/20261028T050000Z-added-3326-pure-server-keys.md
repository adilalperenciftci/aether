- **The pure-Aether TLS server signs with any key a certificate carries.**
  It took ECDSA P-256 alone, so an RSA, P-384, P-521 or Ed25519
  certificate made a server that dropped every connection at the signature
  step. `tls13_server.load_private_key` reads PKCS#8, SEC1 (after an
  `openssl ecparam` EC PARAMETERS block) and PKCS#1 PEM; CertificateVerify
  is signed with the key's own scheme (0x0403, 0x0503, 0x0603, Ed25519, or
  RSA as rsa_pss_rsae_sha256, constant time and blinded) when the client's
  signature_algorithms offers it, and a client that offers none of them gets
  `handshake_failure` (`missing_extension` when it sent none). RSA keys under
  2048 bits are refused, as on the OpenSSL backend. The pure client offers
  ecdsa_secp521r1_sha512 and verifies it. A signing failure now releases
  the whole handshake state and sends `internal_error` (#3326).
  Migration: `tls13_server.accept`'s private key is the handle
  `load_private_key` returns (free it with `free_private_key`), not the raw
  P-256 scalar; `parse_ec_private_key_pem` stays as the low-level P-256
  reader.
