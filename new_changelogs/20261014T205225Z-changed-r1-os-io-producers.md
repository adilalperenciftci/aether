- **std.os, std.io and std.casper hand back counted strings.** The C side
  of `os.exec`, `os.run_capture`, `os.run_full`, `os.run_pipe_drain_and_wait`,
  `os.getenv`, `os.which`, `os.getcwd`, `os.temp_dir`, `os.platform`,
  `os.arch`, the two ISO-8601 clocks, `io.read_file`, `io.getenv`,
  `io.errno_message` and the three casper lookups returned a plain
  `malloc`'d buffer, which `string.release` cannot free and which held no
  length. Each returns a counted `AetherString` now, adopting its buffer
  where it already has one, and is declared `@heap`, as are the
  `string_concat` and `os_getenv` redeclarations in std.os, std.io,
  std.audit, std.casper and std.cas. A capture keeps an embedded NUL
  (`os.run_full` and `os.run_capture` read as truncated at it before),
  and the memory cap's counter returns to where it was once the string
  is released. A C caller reads the result through `aether_string_data`
  and releases it with `string_release`. Stage 2 (R1) of the ownership
  model.
