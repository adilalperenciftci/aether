- **`ae fmt --short-names` writes `json.free(v)` for `json.json_free(v)`.** A
  call that names its module twice is rewritten to the short form where the
  compiler resolves both to the same declaration, and nothing else changes,
  the layout included. `aetherc --emit=short-names` lists those calls of a
  file as `LINE:COLUMN:ns_x:x`; a long name whose short twin is another
  function (std.string's `string.string_join` beside `string.join`) and one
  whose short form starts with a digit (`sha3.sha3_256_hex`) are not listed,
  and a file that does not compile keeps its names. Downstream projects run
  the same command instead of editing by hand (#2976).
