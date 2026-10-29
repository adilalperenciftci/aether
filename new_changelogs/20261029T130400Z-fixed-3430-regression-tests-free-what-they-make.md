- **Regression tests free what they allocate.** Three tests never gave their
  `ref` cells to `ref_free`, one never released the closure boxes it stored
  in raw `ptr` fields (`release_closure`), and one never freed the INTEGER
  it read (`bignum.free`). The macOS leaks gate passed some of them only
  while a stale pointer still reached the blocks (#3430).
