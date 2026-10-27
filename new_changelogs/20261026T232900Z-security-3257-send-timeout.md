- **A client that stops reading its response is cut off.** Nothing bounded
  a send: the worker path wrote with a blocking send and no send timeout, so
  a client that never read held a worker for as long as it kept the
  connection open, and on Linux and macOS the proxy event loop waited on such
  a client with no deadline. Both now give up after the keep-alive idle
  timeout without progress (30 seconds unless set), as a receive does, and a
  response whose send failed closes the connection instead of keeping it
  (#3257).
