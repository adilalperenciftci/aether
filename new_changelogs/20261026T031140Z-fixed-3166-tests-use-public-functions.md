- **Tests call std's public functions, not its raw C bindings, and the
  raw-calls gate covers them.** 81 test files re-declared or called a std
  module's `*_raw` externs (mostly `http_server_start_raw` and
  `http_server_bind_raw`, under a comment that the wrapper's result could
  not be discarded in a receive handler, which `_ =` does). Each now calls
  the public function, its error checked where the raw result was, and
  several old tests that only printed on success now fail on a wrong
  result. `make check-raw-calls` runs over tests and examples too, reports a
  module's binding re-declared outside it, and takes `// raw-ok: <why>` on a
  test of an escape hatch itself (#3166).
