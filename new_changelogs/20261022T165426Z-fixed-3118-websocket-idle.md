- **std.http's server keeps a quiet WebSocket open, and a WebSocket client
  whose peer has gone is told so rather than killed.** An upgraded
  connection kept the receive timeout the server sets on every HTTP
  connection (the keep-alive idle timeout, 30 s by default), so a handler's
  blocking `ws_recv` took a client quiet that long for a close and returned
  -1. The server clears it once the upgrade has gone out; `ws_recv_timeout`
  still bounds a wait a handler wants bounded. And a send on a connection
  the peer had closed raised SIGPIPE, which on Linux killed a client
  process (one that runs no server, so nothing had ignored it); it fails
  with -1 now (#3118).
