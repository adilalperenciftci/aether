- **std.http's server streams a chunked response, sends SSE comments, and
  reads back a response's status.** `http.response_begin_chunked(res)`
  sends the head with `Transfer-Encoding: chunked` and takes the connection
  over, as `response_upgrade_sse` does (TLS included); `chunked_write` and
  `chunked_end` send the body. `http.sse_comment(sse, text)` sends a
  keep-alive line clients ignore. `http.response_get_status(res)` returns
  the status a handler has set (#3109).
