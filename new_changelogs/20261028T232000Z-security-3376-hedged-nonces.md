- **Hedged signing nonces, and the mTLS client checks its signature too.**
  The TLS CertificateVerify signatures used deterministic nonces (RFC 6979
  for ECDSA, RFC 8032 for Ed25519), so two signatures of one message shared
  one, and a fault in either gave the key away. Each signature now mixes 32
  fresh random bytes into the nonce: `ecc.ecdsa_sign_hedged` and the
  curves' `ecdsa_sign_hedged` (RFC 6979 section 3.6, the extra input k'),
  and `ed25519.sign_hedged`. Whatever those bytes hold, the nonce is no
  weaker than the deterministic one, and a verifier cannot tell the
  difference. `ecdsa_sign` and `ed25519.sign` stay deterministic and keep
  their RFC vectors. The mTLS client (`tls13_client.connect_mtls`) now
  checks its CertificateVerify against its certificate's key before
  sending it, as the server does: one that does not verify ends the
  handshake with `internal_error`, and no Finished follows. Before, it sent
  the signature, and learnt of the server's `decrypt_error` only on its
  first read (#3376).
