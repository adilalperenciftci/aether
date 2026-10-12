- **std.http's server answers a request line that is not HTTP with 400 and
  closes the connection.** `THIS IS NOT HTTP` was taken for a request (method
  `THIS`, path `IS`), answered 404, and the connection kept open for a next
  request the client never sends, so the client sat on it until its own
  timeout. A request line whose version is not `HTTP/1.0` or `HTTP/1.1`, and
  any request that does not parse, is now answered `400 Bad Request` with
  `Connection: close` (#2760).
