- **Concurrent sandboxed child launches no longer share one grant transport.**
  The Linux and FreeBSD `spawn_sandboxed` backends now allocate each call an
  exclusively created shared-memory name, so overlapping launches cannot
  overwrite or unlink each other's serialized grants.
