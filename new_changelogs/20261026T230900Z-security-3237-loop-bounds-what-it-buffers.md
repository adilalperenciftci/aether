- **The proxy event loop bounds what a request makes it buffer.** On Linux
  and macOS it grew a connection's buffer for as long as a client kept
  sending header bytes without a blank line, and read a declared
  Content-Length whole before anything looked at it, 2 GiB declared, 2 GiB
  buffered. A head that has not ended within the worker path's 16 KiB
  connection buffer, and a body declared larger than the proxy mount's body
  cap, now go to the worker path, which closes on the first and streams the
  second, where the proxy refuses it with 502 unread (#3237).
