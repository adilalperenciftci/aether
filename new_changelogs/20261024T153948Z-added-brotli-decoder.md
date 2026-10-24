- **`std.brotli` decodes.** `decompress` / `decompress_max` (one-shot) and
  `decompress_stream_new` / `_write` / `_finish` / `_free` (streaming) wrap the
  system libbrotlidec. Every decode takes a cap on what it will produce
  (`max_bytes`, 0 = a 1 GiB ceiling), so a few hundred bytes of `br` cannot
  expand into gigabytes (CVE-2025-6176, urllib3's CVE-2025-66471). Truncated
  input, corrupt input and bytes after the end of the stream are errors, and
  `decompress_stream_finish` reports a stream that was cut short. The decoder
  refuses to run on a libbrotlidec without the CVE-2026-111497
  ("broccoli2shell") fix for its out-of-bounds write: `decoder_available()`
  asks the library itself, so distro backports that keep the old version number
  pass. Large-window streams stay refused. Building with brotli now needs
  libbrotlidec beside libbrotlienc; both come in the same distro package.
