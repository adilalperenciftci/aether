- **SHA-2 digests and fresh keys no longer pass through a string
  (#2600, #3293).** `sha2.final_bytes` (and so every HMAC, HKDF and the
  RFC 6979 nonce derivation) copied the digest into a string and back with
  `bytes.copy_from_string`, whose C side asks whether its source is a
  string by reading the source's first four bytes: a branch on HMAC's
  secret state, which the constant-time test found in P-256 signing, and a
  misread of any digest that happens to start like a string header. The
  digest now stays in its byte buffer. The TLS client and server key shares
  and randoms and the ML-KEM seeds went the same way through
  `cryptography.random_bytes`; they use the new
  `cryptography.random_buffer(n) -> (bytes, err)`, which fills a `std.bytes`
  buffer straight from the OS CSPRNG.
