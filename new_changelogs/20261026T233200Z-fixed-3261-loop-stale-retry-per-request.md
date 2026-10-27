- **Every request on the proxy event loop gets its stale-connection
  retry.** On Linux and macOS the loop retried a dead pooled upstream
  connection once per client connection: after the first such retry, later
  requests on the same client connection that drew a dead pooled connection
  were answered 502. The retry is now each request's, as on the worker path
  (#3261).
