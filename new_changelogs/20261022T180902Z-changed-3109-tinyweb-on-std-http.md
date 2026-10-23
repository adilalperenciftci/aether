- **contrib.tinyweb serves its WebSocket, SSE and chunked endpoints through
  std.http, on the server's own port.** It had listeners on ports of their
  own, whose accept loops a program had to start beside `tw_start`, and a
  frame codec that took one read for a whole frame, had no 64-bit length,
  answered no ping and took an empty frame for a close; its SSE writes never
  reported a client that had left, and `chunked_start` needed a raw socket
  an endpoint does not have. `with_timeout`, `with_keep_alive` and
  `on_stats` were stored and never applied. Now:
  - `web_socket` handlers get every message whole (any length, binary ones
    zero bytes and all), pings are answered, a quiet connection stays open,
    and `ctx` is a map the connection's messages share; reply with
    `http.ws_send_text` or `http.ws_send_binary`.
  - `sse_send`, `sse_send_event` and `sse_comment` return 0, or -1 once the
    client has gone.
  - `chunked_start(res, status)` returns `(stream, err)`, and `write_chunk`
    and `chunked_end` take the stream.
  - `with_timeout` and `with_keep_alive` set std.http's keep-alive, and
    `on_stats` gets a record of each endpoint request, whose accessors now
    return a `string` or an `int`.
  - Removed: `web_server_with_ws`, `web_server_full`, `with_backlog`,
    `with_ws_backlog`, `on_error`, `on_server_error`, `on_ws_timeout`,
    `on_ws_error` (stored, never called), the `WS_OPCODE_*` constants, the
    frame and accept-loop functions (`ws_send_frame`, `ws_read_frame`,
    `ws_accept_loop`, ...), `ws_handshake.c` and `ws_client.ae` (std.http's
    `ws_connect` is the client) (#3109).
