- **A statement call returning a struct that owns strings, with a fresh-string
  argument, compiles again.** Since 0.793 the call was both "discarded" (its
  argument wrap yielded `(void)_ad_r`) and kept in a statement struct
  temporary to destroy, so the C compiler rejected assigning void to the
  struct: `chk(box(fresh("a")), fresh("a"))`, and the std.spec chain
  `expect_str(f()).to_equal_str(g())` with a fresh `g()`. A call the statement
  keeps in a temporary now yields its value.
