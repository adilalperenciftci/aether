- **The proxy event loop no longer spins on the poll() backend.** On a POSIX
  system without epoll or kqueue (Cygwin, for one) the loop left interests
  registered that the connection no longer waited on: write interest on a
  client after a send that had to wait, and read interest on a client while
  its request waited on the upstream. Such a backend reports a ready
  descriptor on every wait, so the driver ran flat out, about 20000 to 30000
  wakeups a second for one idle connection. Each descriptor now holds only
  what its connection's state waits on there; epoll and kqueue are
  unchanged (#3258).
