- **The proxy event loop frees what each proxied request builds.** On Linux
  and macOS the loop dropped the proxy exchange's outbound request and its
  URL instead of freeing them, so every proxied request leaked its URL and
  every one with a body leaked a copy of the body (50 POSTs of 2000 bytes:
  100000 bytes) for as long as the server ran. They are freed once each
  attempt is over, as the worker path frees them after its send (#3242).
