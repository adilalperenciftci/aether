- **`http.server_set_multi_accept` turns on multi-accept, and it starts after
  `server_bind`.** In actor dispatch mode the server can open one
  `SO_REUSEPORT` listener per core on its one port. Nothing could turn it
  on, and forced on it failed after a `server_bind` ("cannot open
  SO_REUSEPORT listener 0") and gave each listener a port 0 of its own
  without one. A bound socket is now the first listener and gives the
  others its port, and a port 0 is resolved once (#3194).
