- **A proxy retry's backoff no longer stalls the event loop.** The proxy
  exchange slept the backoff before a retry itself, and on Linux and macOS
  the proxy event loop drives that exchange on its driver thread, so every
  connection the driver held waited out the backoff, up to 10 seconds. The
  exchange now hands the wait to its caller: the worker path sleeps it, the
  event loop sets a timer and serves its other connections meanwhile
  (#3232).
