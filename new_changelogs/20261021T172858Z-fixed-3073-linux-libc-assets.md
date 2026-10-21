- **`ae add` distinguishes glibc and musl Linux binary packages.** Automatic
  selection uses `linux-x86_64-musl` / `linux-arm64-musl` for musl builds of
  `ae`, preserving `linux-x86_64` / `linux-arm64` for glibc. Explicit release
  targets retain their libc identity, and missing assets or checksums do not
  fall back to the other libc. Binary caches record their installed target;
  incompatible or legacy targetless caches are refused without changing their
  bytes. Use a separate `HOME` per target or remove an old binary cache and
  fetch it again (#3073).
