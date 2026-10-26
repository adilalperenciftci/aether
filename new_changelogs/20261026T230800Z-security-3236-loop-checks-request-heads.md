- **The proxy event loop checks a request head as the worker path does.** On
  Linux and macOS it read Content-Length alone and forwarded heads the
  worker path refuses: whitespace between a header's name and its colon
  (`Content-Length : 2`, which a front end may read as a length where this
  server saw none), an obs-fold continuation line, a signed Content-Length,
  more headers than the parser holds, and a header line too long for it,
  whose remainder was forwarded upstream as the request body. Both paths now
  run one check (`http_request_head_check`), and a head the loop does not
  pass goes to the worker path, which answers 400, 414 or 431 (#3236).
