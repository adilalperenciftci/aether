- **An upstream timeout on the proxy event loop counts against the
  upstream.** On Linux and macOS the loop answered a timed out upstream call
  with 504 itself, so the upstream's in-flight count was never decremented
  (an upstream with an in-flight cap stayed full for good), its breaker never
  heard of the failure, and a retry policy never applied. The timeout now
  goes back to the proxy exchange as a failed call, as on the worker path
  (#3250).
