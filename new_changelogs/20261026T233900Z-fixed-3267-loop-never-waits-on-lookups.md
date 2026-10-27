- **The proxy event loop never waits on a name lookup.** On Linux and macOS
  the loop resolved an upstream's name with a blocking getaddrinfo on its
  driver thread for every fresh upstream connection, so a slow resolver
  (seconds for a name that does not exist) stopped every connection the
  driver held. The loop now has a resolver of its own that looks a name up on
  up to four threads of its own while the connection waits and the driver
  serves the rest; the connection stays on the loop, requests waiting on one
  name share one lookup, the upstream timeout covers the wait, and the
  answer is kept, looked up again behind the dials that use it once it is
  ten seconds old and kept in use while lookups fail. A name that does not
  resolve is answered 502, as on the worker path. Adding an upstream looks
  nothing up, and a program that does not proxy starts no resolver thread
  (#3267, #3275, #3276, #3277, #3283, #3284, #3286).
