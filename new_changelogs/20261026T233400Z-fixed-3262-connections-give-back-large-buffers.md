- **A kept-alive connection gives back a large buffer once its request is
  done.** The proxy event loop kept a connection's receive, input and output
  buffers at the largest size any request needed, and the worker path kept a
  read buffer grown for a chunked request body (up to 8 MiB), each for as
  long as the connection stayed open, idle or parked. Both now keep at most
  64 KiB between requests, the bound the client pool keeps a pooled
  connection's receive buffer at (#3262).
