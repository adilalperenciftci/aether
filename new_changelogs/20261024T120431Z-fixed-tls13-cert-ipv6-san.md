- **The pure TLS client checks an IPv6 address against the certificate's
  iPAddress SANs.** `tls13_cert.check_hostname` recognised only dotted IPv4
  literals; any other host went to dNSName matching, so `https://[::1]/`
  failed against a certificate naming `IP:::1`, and a certificate listing
  the *DNS name* `::1` was accepted for the address ::1. An IPv6 literal is
  now parsed (RFC 4291 text form; a zone or an embedded dotted tail is
  refused) and matched against 16-byte SANs only; a host with a colon that
  does not parse is refused, never tried as a name.
