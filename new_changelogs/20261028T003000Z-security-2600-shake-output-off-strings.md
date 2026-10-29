- **SHA-3 and SHAKE output no longer passes through a string (#2600).**
  `sha3.final_bytes` copied the digest into a string and back, as
  `sha2.final_bytes` did; Ed448 signing runs its secret scalar and nonce
  through SHAKE256, and the constant-time test reported the string's
  header check reading them. The output now stays in its byte buffer.
