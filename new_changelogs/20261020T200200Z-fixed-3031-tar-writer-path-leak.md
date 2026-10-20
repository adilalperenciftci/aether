- **std.tar's writer no longer leaks its path.** `tar.writer_create` stored
  a copy of the archive path and then retained it once more, which neither
  `writer_finish` nor `writer_abort` gave back, so every archive written
  leaked its path. The writer's field owns its copy and `heap.free` releases
  it (#3031).
