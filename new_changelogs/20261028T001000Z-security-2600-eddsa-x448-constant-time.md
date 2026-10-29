- **Ed25519, Ed448 and X448 are constant time (#2600, #1298).** Their
  secret-key operations (EdDSA public-key derivation and signing, the X448
  ladder) ran on the variable-time `std.bignum`. They now run on
  `std.cryptography.ecc`'s fixed-width field: the complete Edwards formulas
  of Bernstein, Birkner, Joye, Lange and Peters with the fixed-window
  scalar multiplication that reads every table entry, S = r + k a mod L on
  fixed-width limbs, and an X448 ladder of 448 masked swaps. Per operation
  with the default `ae build` (was, on `std.bignum`): Ed25519 sign 665 us
  (7850), verify 410 us (8350); Ed448 sign 2.3 ms (23.2), verify 1.6 ms
  (25.5); X448 1.0 ms (6.6). The Wycheproof Ed25519 and X448 drivers sweep
  every case (they sampled every 5th and 25th), and the constant-time test
  covers EdDSA signing, X25519 and X448.
