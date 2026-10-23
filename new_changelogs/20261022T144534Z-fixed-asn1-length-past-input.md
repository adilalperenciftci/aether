- **A DER length past the input is refused, however large.** std.cryptography.asn1
  checked a TLV's length as `pos + length > len`; a four-byte length that is
  negative or near 2^31 wrapped that sum past the check, and the reader went
  on with content it did not have. An INTEGER declaring 0x7fffffff bytes
  reached `bignum.from_bytes`, which panicked (Wycheproof's DER ECDSA
  signatures). The length is now compared with what is left of the input.
