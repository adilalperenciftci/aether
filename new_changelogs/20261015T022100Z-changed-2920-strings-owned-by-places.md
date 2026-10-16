- **Every string local owns what it holds, and every string a function
  returns is the caller's.** A store moves a fresh string, or an owning
  local at its last use, and copies anything else (a literal is static and
  never copied); a `string` result and every `string` position of a tuple
  is handed over from every return. `string.free(x)` releases what `x`
  holds and leaves it empty. The C byte getters behind std's codecs,
  digests and reads (`zlib_get_inflate_bytes` and the like) return `ptr`:
  bytes whose length C reports separately are not a C string (#2920).
