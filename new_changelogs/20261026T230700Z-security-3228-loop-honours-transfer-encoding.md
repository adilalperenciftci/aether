- **The proxy event loop honours Transfer-Encoding.** On Linux and macOS it
  framed a request by Content-Length alone: a chunked request body was
  forwarded as empty and its chunks then parsed as the next request, and a
  request carrying both Content-Length and Transfer-Encoding was forwarded
  with Content-Length bytes as its body, where the worker path refuses it
  with 400 because the two lengths are what request smuggling is built
  from. A request with Transfer-Encoding now goes to the worker path, which
  decodes a chunked body and refuses the rest (#3228).
