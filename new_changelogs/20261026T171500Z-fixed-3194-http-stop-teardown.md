- **`http.server_stop` no longer tears down what the server thread owns.**
  In actor dispatch mode a stop destroyed the accept pollers and closed
  multi-accept's listeners while the accept loops still ran, and the server
  thread then did it again: on macOS a closed kqueue wakes its waiter at
  once, so the server thread freed the arrays the stop was walking, and
  each listener and poller was closed twice, the second time possibly
  closing a descriptor opened since. The server thread now gives them back
  alone, once its accept loops see the stop. Multi-accept is also refused
  where the kernel does not spread connections across the listeners
  (macOS, OpenBSD, NetBSD, as on Windows): it runs on Linux, DragonFly and
  FreeBSD (`SO_REUSEPORT_LB`) (#3194).
