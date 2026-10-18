- **`fs.fs_get_read_binary()` returns `ptr`, so the bytes after a NUL
  survive.** The split-accessor getter was declared `-> string`, and since
  a string local owns its value (0.818.0) `s = fs.fs_get_read_binary()`
  copied the borrowed buffer as a C string, up to the first NUL; a
  length-aware copy from `s` then read past that short copy (a PNG loader
  got null for every image). It now returns `ptr`, as the other byte
  getters whose length C reports separately do since #2920. contrib's
  `sqlite_get_blob_bytes`, `avc_get_frame_bytes` and `avc_audio_get_pcm`
  had the same declaration, and `sqlite.column_blob`, `avcodec.next_frame`
  and `avcodec.audio_pcm` bound them to a local before their length-aware
  copy, so a blob, frame or PCM buffer with a NUL in it came back right in
  length and wrong after the first NUL (read past the end of the short
  copy). They return `ptr` too. Found by aebiten.
