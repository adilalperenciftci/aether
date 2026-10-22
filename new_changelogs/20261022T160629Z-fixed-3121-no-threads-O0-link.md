- **A no-threads stdlib built at -O0 links.** `http_park_resume` was
  compiled in every build and calls `http_pool_submit_conn`, which only a
  threaded build defines. At -O2 GCC dropped the unused function and the
  reference with it; at -O0 `make stdlib EXTRA_CFLAGS='-DAETHER_NO_THREADING
  -O0'` failed to link the shared runtime on Windows and left an unresolved
  symbol in the Linux one. It is compiled where its only caller is, and a
  test compiles every libaether source at -O0 in both modes and fails on any
  symbol a no-threads object needs that only threaded objects define
  (#3121).
