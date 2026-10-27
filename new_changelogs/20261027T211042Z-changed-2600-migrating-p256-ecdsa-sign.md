- **Migrating: `p256.ecdsa_sign` takes no nonce (#2600).** The nonce is
  derived by RFC 6979 from the key and the digest, so the parameter is
  gone, and so is the `k` argument of `tls13_cert.sign_client_cert_verify_ecdsa_p256`
  and `sign_server_cert_verify_ecdsa_p256`. Drop the argument and the code
  that drew it:

  ```aether
  k = random_32_bytes()
  r, s = p256.ecdsa_sign(priv, digest, k)     // before
  r, s = p256.ecdsa_sign(priv, digest)        // now: the same digest gives the same signature
  ```

  `ecdsa_sign` returns `(null, null)` for a private key outside [1, n-1]
  (check one with `p256.private_key_valid(priv)`), and `ecdh` and
  `scalar_mult` return null for a public point that is not on the curve
  (`p256.public_key_valid(x, y)`). The digest may be any length: its leftmost
  256 bits are signed, as FIPS 186-5 says.
