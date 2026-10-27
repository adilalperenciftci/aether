- **`tcp.set_read_buffer(sock, bytes)`** sets a connected socket's receive
  buffer (SO_RCVBUF), which also stops the kernel growing it by itself while
  data arrives. A client that must stop taking bytes when it stops reading,
  such as a test of a server's send timeout, sets it small (#3257).
