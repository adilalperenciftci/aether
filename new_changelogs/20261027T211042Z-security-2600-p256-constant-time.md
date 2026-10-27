- **P-256 signing and ECDH are constant time, with RFC 6979 nonces
  (#2600, #1298, #3291).** `std.cryptography.p256` ran on the variable-time
  `std.bignum`: every bit of the private key and of the nonce chose a branch,
  and the pure TLS 1.3 server and the mTLS client signed with it. It now runs
  on the new `std.cryptography.ecc`, fixed-width Montgomery field arithmetic
  on 32-bit limbs with no allocation, the complete addition formulas of
  Renes, Costello and Batina, and a fixed 4-bit window scalar multiplication
  that reads every table entry. `ecdsa_sign` derives its nonce by RFC 6979
  (HMAC-DRBG over SHA-2) and takes no nonce from its caller. A new CI job,
  "Crypto constant-time (Valgrind)", runs `tests/integration/crypto_ct_valgrind`
  with the secret inputs marked undefined for memcheck and fails on any
  branch or memory index that depends on them; on the old code it reported
  68. `ecdh`, `scalar_mult` and `ecdsa_verify` now refuse a public point off
  the curve or with a coordinate of p or more: before, `ecdh` computed with
  any point it was given, the invalid-curve attack (#3291; all 355
  Wycheproof `ecdh_secp256r1_ecpoint` cases now run, 16 of them failed
  before). Per operation, with the default `ae build`: sign 415 us (was
  4050), verify 470 us (was 7850), ECDH 365 us (was 3900), so the
  Wycheproof P-256 ECDSA drivers sweep all their vectors. The TLS client's
  random-bytes helper also returned zeros when the CSPRNG failed, which would
  have made its key shares predictable; it fails the handshake now.
