- **AES and GHASH are constant time, and AES-GCM is 15 times faster
  (#2600, #1298).** The AES core indexed a 256-byte S-box with key- and
  data-dependent bytes, which leaks the key through the cache; it is now
  the 64-bit bitsliced AES of BearSSL's `aes_ct64` (the Boyar-Peralta S-box
  circuit, four blocks per pass), about 185 MB/s in CTR mode. GHASH's
  GF(2^128) multiply branched on the bits of the state and of H; it is a
  masked shift-and-add on 64-bit halves now, which took AES-128-GCM from
  1.5 MB/s to 23 MB/s. Every AEAD tag check (GCM, CCM, EAX, OCB,
  ChaCha20-Poly1305) and the AES key-wrap integrity check compare all bytes
  and declassify one verdict. The constant-time test covers AES-128/256,
  AES-GCM seal and open, ChaCha20-Poly1305 seal and open, Poly1305,
  HMAC-SHA-256, HKDF and SHA-256 with their keys secret, which is the
  Poly1305 audit #1298 asked for.
