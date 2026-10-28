- **The pure TLS client follows a HelloRetryRequest for secp384r1 and checks
  the ServerHello's group after one (#3369).** The client put a key share on
  every group it offered, so no server ever had a group to ask for, and
  after a HelloRetryRequest it did not check that the ServerHello used the
  group it asked for (RFC 8446 4.2.8). It now names secp384r1 in
  supported_groups without a share, as BoringSSL does, answers a
  HelloRetryRequest for it with a P-384 share alone, and refuses with
  illegal_parameter a ServerHello whose group has no share in the
  ClientHello it answers. New `tls13_hs.client_hello_offer` (a ClientHello
  naming one group without a share) and `tls13_hs.GROUP_SECP384R1`.
