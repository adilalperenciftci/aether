- **A null string reads as the empty text everywhere, and `== null` is a
  pointer test.** An unset `os.getenv` result printed as `(null)`,
  interpolated as `(null)`, and compared equal to a real string reading
  `"(null)"`; `"" != null` was false. Now a null string reads as `""` for
  `==`, `!=`, ordering, `string.equals`, `string.compare`, printing and
  interpolation, while `s == null` and `s != null` against the `null`
  keyword compare the pointer, so unset and empty stay apart (#3129).
  std.cas, std.cryptography.tls13_client and thirteen tests dropped the
  `== null || == ""` pairs they carried to work around it.
