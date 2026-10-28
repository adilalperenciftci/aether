- **The pure TLS stack sends the dummy change_cipher_spec of middlebox
  compatibility mode (#3322).** The client always sends a non-empty
  legacy_session_id, which RFC 8446 4.1.2 ties to that mode, but never sent
  the dummy change_cipher_spec D.4 asks for, so BoringSSL (and middleboxes
  that expect TLS 1.2's shape) refused it. The client now sends it before
  its second flight (an alert included), or right after the ClientHello
  when it offers early data; the server sends one right after its
  ServerHello when the client's legacy_session_id is not empty.
