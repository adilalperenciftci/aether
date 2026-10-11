- **A module's imports are its own.** In a module, a selective import of an
  extern-backed name (`import std.http (server_create)` for `extern
  http_server_create`) failed with E0301, although the glob form and a
  program file's selective import both worked; it now binds the name as they
  do. And a program's selective or glob import no longer reaches into the
  modules it imports: a module calling a bare `server_create` without
  importing `std.http` built or failed depending on which program imported it
  (aeo's runner and agent disagreed). It now fails with E0301 in every
  program, as a qualified name already did (#2614).
