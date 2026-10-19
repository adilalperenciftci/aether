- **EOF-aware line input in `std.io`.** `io.fd_read_line_status(fd)` returns
  `(line, eof, err)`, distinguishing blank lines from clean EOF and returning
  an unterminated final line with `eof=true`. Results are owned strings that
  survive later reads and descriptor closure. CR/LF handling and the existing
  two-result `fd_read_line` API remain unchanged.
