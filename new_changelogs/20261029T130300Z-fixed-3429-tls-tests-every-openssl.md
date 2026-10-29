- **The TLS tests pass with every OpenSSL CI runs.** The signature check
  read only the scheme names OpenSSL 3.2 and later print, and Ubuntu's 3.0
  names a signature by its type and digest; the resumption test started
  `s_server -www -early_data`, which 3.0 refuses; the key test made its
  PKCS#1 fixture with `-traditional`, which macOS's LibreSSL does not know
  and does not need. Each now reads what every one of them says, and a
  3.0 host reports its 0-RTT-against-OpenSSL cases as skipped (#3429).
