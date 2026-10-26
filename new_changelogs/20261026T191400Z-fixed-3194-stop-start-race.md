- **A stop as the server starts closes its socket once.** Multi-accept takes
  the socket `server_bind` made as its first listener, and a stop that came
  between the read and the clear closed it, which the start's release then
  closed again. Both now take it under the server's lock (#3194).
