- **The OpenSSL server backend sends the certificate chain.** It loaded the
  certificate file with `SSL_CTX_use_certificate_file`, which reads the first
  certificate alone, so the intermediates in a CA's bundle never reached the
  client, and a client that did not already hold them refused the server. The
  pure backend sent the whole chain, so the two backends served different
  chains from one file. Both now send the leaf and every certificate after it
  (#3370).
