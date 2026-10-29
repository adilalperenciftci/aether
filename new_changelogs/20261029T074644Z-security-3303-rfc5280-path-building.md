- **TLS certificate path construction now enforces issuer path limits and
  validity.** `std.cryptography.tls13_cert` parses `pathLenConstraint`, rejects
  expired or not-yet-valid intermediates, and performs bounded backtracking
  when more than one certificate can issue the current path node. The remaining
  #3303 work is extendedKeyUsage, critical-extension and name-constraint policy.
