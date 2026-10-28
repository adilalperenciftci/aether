- **Path validation measured against x509-limbo and bettertls, and against
  OpenSSL; what they found is fixed (#1298).** `std.cryptography.tls13_cert`
  runs both corpora in Linux CI (`tests/conformance/x509_limbo`, pinned to a
  commit and a SHA-256, fetched into a cache): all 9572 bettertls cases
  agree, and `expected.txt` gives, for each limbo case that is skipped (CRLs,
  ML-DSA) or does not agree, the reason and OpenSSL's verdict. The two TLS
  backends accept the same chains except where OpenSSL accepts something
  unsafe, which the pure backend refuses. Fixed on the way: path validation
  accepted RSA keys under 2048 bits, DSA and P-192 keys, and EC keys with
  explicit curve parameters; a wildcard SAN such as `*.example.com` passed a
  CA's excluded `bar.example.com` (CVE-2025-61727, which OpenSSL 3.6.4 still
  accepts); mailbox, URI, directoryName and unrecognised name-constraint
  forms were ignored rather than applied or refused; malformed names or
  constraints, and an empty permittedSubtrees, were read as well formed;
  name-constraint checks had no bound (2048 subtrees against 2048 names is
  four million comparisons; now 250000, as Go and rustls-webpki); `*.com`
  matched every .com host; and a critical key identifier or authority
  information access, or a CA with an empty subject, was accepted.
