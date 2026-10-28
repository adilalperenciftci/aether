- **The pure TLS client refuses a message its server's flight cannot hold
  at once (#3367).** The client read the encrypted flight until a Finished
  arrived and only then checked what came before it, so a server that sent
  its Finished as another message type (or any message that does not belong
  in the flight) left the client waiting until the connection closed or
  timed out. Only EncryptedExtensions, CertificateRequest, Certificate,
  CertificateVerify and Finished may come there; any other type is now
  unexpected_message as soon as its header arrives.
