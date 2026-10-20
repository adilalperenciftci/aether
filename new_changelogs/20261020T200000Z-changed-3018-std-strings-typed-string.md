- **Breaking: every std function that returns a string is typed `string`,
  and a `ptr` no longer renders.** These returned their counted string as a
  `ptr` and now return `string` (owned, `@heap`), with the same C ABI:
  `string.new`, `string.from_cstr`, `string.from_literal`, `string.empty`,
  `string.new_with_length` (also as declared in std.brotli,
  std.cryptography, std.encoding, std.fs, std.http, std.lzf, std.zlib,
  std.zstd and contrib's avcodec and sqlite), `string.from_char`,
  `string.from_int`, `string.from_long`, `string.from_float`,
  `string.from_int_radix`, `string.pad_start`, `string.pad_end` and
  `string.format_list`; std.tar's name helpers too. `string.array_get`
  returns the array's characters as a borrowed `string`, so a local that
  keeps one copies it and it outlives `string.array_free`. As a `ptr`
  nothing released these results, so each call leaked its string; as a
  `string` the place that takes it owns it. A program that stored one in a
  `ptr` local or field is now refused (E0200, E0902): keep it in a
  `string`. Interpolating or printing a `ptr` is error E0200 (#3018): it was
  rendered as a C string whatever it pointed at, a list or a buffer
  included. A `ptr` that holds a C string is read with
  `string.from_ptr(p)`, and a container's string with `list.get_string` or
  `map.get_string`.
