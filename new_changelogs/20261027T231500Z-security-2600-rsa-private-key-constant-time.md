- **RSA private-key operations are constant time and blinded (#2600).**
  `std.cryptography.rsa`'s `raw_decrypt`, and through it `decrypt_pkcs1`,
  `decrypt_oaep`, `sign_pkcs1` and `sign_pss`, ran std.bignum's
  variable-time `mod_pow` on the private exponent. They now use Montgomery
  arithmetic on fixed-width limb vectors and a fixed 4-bit window
  exponentiation that reads every table entry, with the base blinded by a
  fresh random r. PKCS#1 v1.5 and OAEP decryption check the padding without
  an early exit (the Bleichenbacher and Manger timing oracles). A 2048-bit
  private-key operation takes about 11 ms with the default `ae build` (27 ms
  before). New `rsa.key_from_bytes(n, e, d)` builds a key from big-endian
  byte strings without putting d through std.bignum; `raw_decrypt` and the
  signers return null (or an error) for a public-only key instead of
  crashing. The constant-time test covers all four private-key paths.
