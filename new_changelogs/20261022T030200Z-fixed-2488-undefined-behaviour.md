- **Undefined behaviour the UBSan run of the test corpus found is gone.**
  `mem.get_u64_le` and `mem.get_u64_be` overflowed a signed integer for a
  top byte of 128 or more; HTTP basic auth's base64 decoder and h2c's
  HTTP2-Settings decoder overflowed an int after six characters; std.lzf
  compared two bytes through an unaligned `u16` load; the shared map read
  its header through a plain char. The values were right on the compilers
  in use, but C leaves each undefined, so a compiler was free to break
  them (#2488).
