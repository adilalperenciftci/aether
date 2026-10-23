- **`make check-raw-calls`, run by `make ci`: no std or contrib file calls a
  raw C binding another module declares.** A module binds C through
  `*_raw` externs and builds its public functions on them; a caller in
  another module that names the binding skips the error results, the
  ownership and the bounds the public function adds. The checker, in
  Aether (tests/raw_calls/check.ae), reports each such call and selective
  import, skipping a module's own bindings, helpers named like one,
  comments and strings, and runs its self-test over a fixture first
  (#3107).
