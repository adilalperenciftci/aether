- **The TinyWeb examples print their usage hints once the server is
  listening.** `example_auth`, `example_composition`, `example_sse`,
  `example_static` and `example_websocket` printed curl hints before
  `tw_start`, so the hints appeared even when the bind failed, and named a
  hard-coded port. They now print from `http.monitor`'s `listening` callback
  with the bound port, as `example_app` does.
