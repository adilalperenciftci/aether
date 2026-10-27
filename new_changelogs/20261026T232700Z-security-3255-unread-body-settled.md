- **A streamed request body left unread is never read as the next
  request.** A body over the server's 16 KiB connection buffer reaches the
  middleware streamed. One that a middleware answered without reading (the
  proxy refusing a body over its cap, a 429 from the rate limiter, the
  proxy's 400 for a body that stopped short) stayed on the kept connection
  and was parsed as the next request, so a body carrying a request of its
  own had that request served: request smuggling, on a bare proxy gateway on
  Linux and macOS too since such requests go to the worker path. Every
  response now settles the body first: a remainder of 64 KiB or less is read
  and dropped, and past that the response says `Connection: close` and the
  connection closes in stages. A route handler that ignores a larger body no
  longer has the server read all of it to keep the connection (#3255).
