- **std.http's server sends every byte of a response.** On a plaintext
  connection each response, WebSocket frame and SSE event went out as one
  send(2), which can take fewer bytes than asked when a signal or a send
  timeout cuts it off once part of the buffer is out; the rest never went,
  and the client got a truncated response. The server now sends until every
  byte is out, retrying an interrupted send (#3108).
