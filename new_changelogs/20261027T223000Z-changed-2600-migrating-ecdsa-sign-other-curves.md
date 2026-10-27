- **Migrating: `p384`, `p521` and `secp256k1`'s `ecdsa_sign` take no nonce
  either (#2600).** As for `p256`: drop the third argument, and the
  signature of a digest under a key is always the same one (RFC 6979).

  ```aether
  r, s = p384.ecdsa_sign(priv, digest, k)     // before
  r, s = p384.ecdsa_sign(priv, digest)        // now
  ```

  P-521 also changes how the digest is read: the leftmost 521 bits of the
  buffer, as FIPS 186-5 says, so a SHA-512 digest is passed as its 64
  bytes. The old API took a 66-byte buffer as a number, and callers padded
  the digest with two zero bytes; that buffer is now read as a 528-bit
  digest and truncated, which signs a different number. `ecdsa_verify`
  reads the digest the same way. secp256k1's `s` is as computed, not in
  Bitcoin's low-S form.
