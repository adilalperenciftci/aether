- **A request head over 16 KiB is answered 431.** A head that did not fit
  the server's connection buffer was refused by closing the connection with
  nothing written and the rest of the head unread, so the client got no
  status and the reset the close sent could destroy the response to a
  request pipelined ahead of it. It is now answered 431 Request Header Fields
  Too Large and the connection closed in stages, as every other refusal of a
  request not read to its end is; the proxy event loop hands such a
  connection to that path (#3252).
