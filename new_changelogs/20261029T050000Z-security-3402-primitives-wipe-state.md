- **Hashes, MACs and ciphers wipe their own state.** Wiping a key was not
  enough while the primitives that used it freed their state as it was:
  after one Ed25519 signature its seed was in SHA-512's freed block, an
  HMAC's key was in its freed padded key, and a shield wrap left the AEAD
  key (a SHA-512 digest) in a freed SHA-2 context. `sha2`, `sha3`, `hmac`,
  `hkdf`, `aes` and `chacha20poly1305` now free every buffer with
  `bytes.wipe_free`, wipe their context structs before freeing them, and
  the C AES wipes its round keys and stack copies with `aether_wipe` (a
  `memset` there was a dead store). New: `mem.wipe(dst, n)`, the
  raw-memory form of `bytes.wipe`. No cost shows at the timer's
  resolution: SHA-256 of 1 MiB 8 ms, of 64 bytes 1 us, HMAC-SHA-256 of 64
  bytes 3 us, before and after (#3402).
