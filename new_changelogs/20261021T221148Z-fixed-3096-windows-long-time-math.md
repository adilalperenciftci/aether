- **The HTTP server, middleware and proxy keep time in 64 bits on Windows.**
  A `long` is 32 bits there, and clock readings, stored times and sums were
  kept in one:
  - The server's metrics overflowed their request-duration sum after 35.8
    minutes of summed request time. The proxy's latency sum overflowed
    after 24.8 days of summed latency (hours on a busy proxy). Their
    counters overflowed after 2^31.
  - A single request longer than 35.8 minutes logged a wrapped duration.
  - The proxy's clock went negative after 24.8 days of uptime and stayed
    negative for as long again. While it was negative, proxy request
    deadlines read as none, so upstream timeouts stopped firing, and cache
    expiry compared across the wrap.
  - A proxy cache TTL past 24.8 days expired the entry as it was stored.
  - A rate-limiter bucket idle for more than 24.8 days did not refill.

  The clocks' products also overflowed: undefined behaviour that only
  happened to wrap. The event loop parsed `Content-Length` into a `long`,
  so a length past 2 GiB read short. `HttpRequestHook`, the C-only request
  hook, now takes `int64_t duration_us` (#3096).
