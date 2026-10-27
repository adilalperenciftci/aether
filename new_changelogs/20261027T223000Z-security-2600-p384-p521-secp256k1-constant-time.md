- **P-384, P-521 and secp256k1 are constant time too, with RFC 6979 nonces
  (#2600, #3291).** `std.cryptography.p384`, `p521` and `secp256k1` run on
  `std.cryptography.ecc` like P-256: signing, ECDH and the scalar
  multiplications no longer branch on the key or the nonce, and the
  constant-time test covers each curve's signing and ECDH. ECDH refuses a
  point off the curve (#3291): every case of Wycheproof's
  `ecdh_secp384r1_ecpoint`, `ecdh_secp521r1_ecpoint` and
  `ecdh_secp256k1_webcrypto` runs. Per operation with the default
  `ae build` (was, on `std.bignum`): P-384 sign 1230 us (7700), verify 1410
  (15500), ECDH 1110 (7400); P-521 sign 3040 (15000), verify 3400 (28600),
  ECDH 2920 (14800); secp256k1 sign 340 (3800), verify 370 (7850), ECDH 285
  (3750). The Wycheproof ECDSA drivers for the three curves now sweep every
  vector instead of every tenth (8 s, 18 s and 4 s at the -O0 of `ae run`).
