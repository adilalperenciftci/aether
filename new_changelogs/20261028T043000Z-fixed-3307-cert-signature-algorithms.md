- **The pure TLS client verifies chains signed with SHA-384 and SHA-512
  RSA, ECDSA on P-521 or with SHA-512, and Ed25519 (#3307).**
  `std.cryptography.tls13_cert` checked certificate (and OCSP responder)
  signatures only for sha256WithRSAEncryption, ecdsa-with-SHA256 on P-256
  and ecdsa-with-SHA384 on P-384, so www.bing.com and www.microsoft.com
  (sha384WithRSAEncryption, as many DigiCert chains) and any chain through a
  P-521 or Ed25519 CA failed with "certificate does not chain to a trusted
  anchor". RSA PKCS#1 v1.5 now takes SHA-256, SHA-384 or SHA-512; ECDSA
  takes any of the three hashes on a P-256, P-384 or P-521 key; Ed25519
  (id-Ed25519) is verified too.
