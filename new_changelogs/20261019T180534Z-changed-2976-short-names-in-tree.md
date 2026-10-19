- **The tree calls its modules by short names.** `ae fmt --short-names`
  rewrote 1,744 calls in 114 files of std, contrib, tests and examples from
  the doubled form (`json.json_free`, `string.string_length`,
  `md5.md5_hex`) to the short one (`json.free`, `string.length`,
  `md5.hex`), only where the compiler resolves both to the same
  declaration. The C each of the 118 files that compile generates is
  byte-identical before and after (modulo `#line`), and so is that of every
  rewritten std module built as one `--lib-package=std` library (#2976).
