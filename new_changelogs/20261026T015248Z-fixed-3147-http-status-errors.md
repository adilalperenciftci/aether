- **`http.get` and the other one-line calls name a failed status.** Every
  response outside 2xx came back as `"http error"` (below 200, `"unexpected
  status"`), so a 404 and a 503 read the same. They now return `"HTTP 404 Not
  Found"`, the status and its registered reason, or the number alone for an
  unregistered code. `http.status_text(code)` gives the reason, and the
  server's table behind it now covers every code IANA registers: a server or
  proxy answering 409 or 429 wrote `Unknown` on its status line, and now
  writes `Conflict` or `Too Many Requests` (nothing for an unregistered code,
  as RFC 9112 allows) (#3147).
