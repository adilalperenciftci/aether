- **A fatal runtime error no longer loses what the program printed last.**
  A panic outside any try, a failed runtime check, a fatal `std.log`
  record, or an out-of-memory the runtime cannot report printed its message
  and called `abort()`, and stdout, fully buffered when it is a file or a
  pipe, was never flushed: glibc's `abort()` flushes no stdio stream, so the
  program's last lines were lost on Linux. Each such path now flushes stdout
  before its message, unless another thread holds it (one blocked writing
  to a pipe nobody reads), so the abort never waits behind it (#3435).
