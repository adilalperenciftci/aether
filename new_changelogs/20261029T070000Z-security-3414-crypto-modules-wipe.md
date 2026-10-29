- **Every cryptography module wipes what it frees.** #3402 made the hash,
  MAC and cipher modules wipe their state; the key exchange and the key
  schedule still freed secrets as they were: X25519's ladder its clamped
  copy of the private scalar on every exchange, the TLS key schedule its
  "derived" salts (one of which gives the master secret, so every
  application traffic key), and `tls13_ks.free_secret` zeroed with a loop
  the compiler may drop. The rule is now the whole tree's: every module
  under `std/cryptography` frees every `bytes` buffer with
  `bytes.wipe_free`, and `make check-crypto-wipe` (run by `make ci`) fails
  on a plain `bytes.free` there. Context structs, Argon2's working matrix,
  ML-KEM's coefficient arrays, BLAKE3's buffers and RSA's limb scratch are
  wiped with `mem.wipe` before they are freed (#3414).
