- **`fs.close` and `fs.read_all` (and `file.close`, `file.read_all`) for the
  handle `open` gives.** The only close was the C binding `file_close`, an
  int, and an open handle could not be read whole. `close` returns `""` or
  the reason, and reports a write the close's flush could not make;
  `read_all` returns the text or the reason. `fs.write` and `file.write`
  report that failed flush too: they said `""` for a write that never
  reached the disk (a full one, `/dev/full`). The C function is
  `file_close_raw`, named as the other raw bindings are, so the C symbol
  `file_close` is free for `file.close`. std.file's README showed a handle
  write the module has no call for; its example now runs as written (#3179).
