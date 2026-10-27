- **A proxied response on the event loop follows the keep-alive policy.** On
  Linux and macOS the proxy event loop sent every proxied response without a
  Connection header and kept the connection open, after a client's
  `Connection: close`, after an HTTP/1.0 request, with keep-alive turned off
  and past `keep_alive_max`, so a client that asked to close, or an HTTP/1.0
  one reading to the end of the connection, waited until it gave up. The loop
  now decides and states it as the worker path does, on the response it
  writes from the upstream's bytes and on the one it builds, and a
  connection it hands to the worker path keeps its request count (#3229).
