- **The proxy event loop never waits on a name lookup.** On Linux and macOS
  the loop resolved an upstream's name with a blocking getaddrinfo on its
  driver thread for every fresh upstream connection, so a slow resolver (seconds
  for a name that does not exist) stopped every connection the driver held.
  An upstream's name is now looked up as it is added to its pool and again
  every ten seconds while it is in use, on a thread of its own; the loop
  dials a numeric address or a name looked up that way, and a request whose
  name has no answer goes to the worker path, whose dial waits (#3267).
