- **`make contrib` replaces each archive in one step.** It wrote objects,
  archives and the manifest in place in `build/contrib`, so a link against
  `build/contrib` while it ran could read an archive half rewritten, two
  runs at once overwrote each other's files, and a link that fell between
  the vendored SQLite veneer and the `libsqlite3.a` it calls into got the
  system library instead; on macOS, whose system library has no
  `sqlite3_enable_load_extension`, that failed the link, and the 0.807.0
  and 0.808.0 macOS release builds with it, so neither release was
  published. Each run now builds in a directory of its own and moves every
  archive into place with a rename, the vendored `libsqlite3.a` before the
  veneer that needs it and the manifest last. `CONTRIB_OUT` builds into
  another directory (#2780).
