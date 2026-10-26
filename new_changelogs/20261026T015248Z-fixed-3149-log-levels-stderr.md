- **std.log exports its levels, logs to stderr on request, and writes a `%`
  as text.** `log.LOG_LEVEL_DEBUG` to `log.LOG_LEVEL_FATAL` replace the bare
  0 to 4 the header described. `log.init("")` and `log.init("-")` log to
  stderr; `""` used to fail with "cannot open log file" and print `[LOG]
  Failed to open log file:`, and a failed open now returns an error naming
  the file and prints nothing. `log.write` handed its message to printf as
  the format, so `"100%s"` crashed: it now writes the text as given (C
  callers format with `log_writef` and the `LOG_*` macros). A second init
  after a stderr target no longer closes stderr (#3149).
