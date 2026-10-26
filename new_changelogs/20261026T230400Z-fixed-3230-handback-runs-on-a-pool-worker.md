- **A request the proxy event loop hands back runs on a pool worker.** On
  Linux and macOS a request a proxy mount does not take (`/metrics`, a health
  check, an admin route, a second mount) went to the worker path on the
  loop's own driver thread, so its route handler, the middleware after the
  mount and the wait for the connection's next request held up every other
  connection on that driver until they returned. The connection now goes to
  the server's worker pool, as an accepted one does (#3230).
