- **An HTTP/2 request carries its connection's peer, local address and TLS
  state.** Each h2 stream's request was built without them, so
  `http.request_remote_addr` read `""`, `http.request_is_tls` 0 and
  `http.request_scheme` `"http"` even over TLS. The HTTP/1.1 dispatcher and
  the h2 dispatch now copy them from the connection through one function
  (#3175).
