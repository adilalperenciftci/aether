- **The proxy event loop keeps hearing its connections on the poll()
  backend.** On a POSIX system without epoll or kqueue (Cygwin, for one) the
  poll backend removed a descriptor after its first event even when it was
  registered with `AETHER_IO_EDGE`, which the poller's contract says stays
  registered, level-triggered, on a backend with no edge mode. The event loop
  registers each connection once for its life, so the third request on a
  kept-alive proxied connection was never read and the client waited for it
  forever. Linux and macOS were not affected (#3214).
