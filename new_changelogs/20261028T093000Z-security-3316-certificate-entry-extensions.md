- **The pure TLS client checks the server's Certificate message (#3316).**
  It accepted any CertificateEntry extension (an unknown type, an SCT it
  never asked for, a server_name out of place, a repeated or empty
  status_request) and did not check that the message's lists fill it. RFC
  8446 4.4.2 and 4.2 make these errors; the client now refuses them with
  unsupported_extension, illegal_parameter or decode_error, and a
  status_request must hold exactly one OCSP response. New
  `tls13_hs.check_certificate(body, offered)` holds the rules.
