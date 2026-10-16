- **A function may not free a string it was passed (E0901).** A `string`
  parameter is borrowed for the call: the caller owns it and frees it.
  `string.free(p)`, `release(p)` or the runtime free bound under another
  name, on any path, released a reference the function did not own, which
  the compiler then had to guess around at every caller. Store the string to
  keep it; a parameter the body re-binds holds a string of its own and may
  be freed. std.jsonpath and contrib.tinyweb free their strings where they
  own them (#2924).
