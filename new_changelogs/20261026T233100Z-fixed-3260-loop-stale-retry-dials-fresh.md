- **A retry after a stale pooled upstream connection dials a fresh one on the
  proxy event loop.** On Linux and macOS the loop sent the request again on
  another connection from the same pool, so when the upstream had closed
  that one too (as it does on an idle timeout) the client got 502. The retry
  now dials a fresh connection, as the worker path's client does (#3260).
