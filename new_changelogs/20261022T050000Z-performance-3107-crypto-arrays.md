- **std.bignum and the cryptography modules hold their buffers as arrays and
  slices, and bignum's modular exponentiation is 2.7x faster.** They kept
  their limbs, message schedules, states and round keys in std.intarr and
  std.longarr handles, read through another module's raw C bindings. The
  fixed-size buffers are now fixed-size array fields and locals (a SHA-2
  schedule is a `long[80]`, an Argon2 block a `long[QWORDS]` struct), the
  sized ones `make([]int, n)` slices, so every index is checked. Measured on
  Windows, gcc -O2, best of four interleaved rounds against the same
  compiler: a 2048-bit `mod_pow` 2.7x faster, ML-KEM-768 +10%, SHA-3 +15%,
  BLAKE2b +14%, 3DES +23%, Streebog +15%, Argon2 +3%, the other hashes and
  ciphers within noise, and Tiger -2% (one index check per 8 bytes it
  feeds). `bignum.test_bit(n, i)` reads one bit in place; p256's scalar
  multiplication read it through the BN struct's layout before (#3107).
