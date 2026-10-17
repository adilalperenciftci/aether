- **A tuple destructure's unread local no longer breaks a `-Wall -Werror`
  build.** `a, _b = pair()` declared `int _b` in the C and never read it,
  which is `-Wunused-variable` under `-Wall` on gcc and clang. The `_`
  prefix is how a program marks a binding unused, and the type checker
  stays quiet about it, but the C compiler did not. std.fs's `remove_tree`
  destructures `k, _s, _m, serr = file_stat(path)`, so every program
  calling it failed under `-Werror`. A destructure local that is
  `_`-prefixed, or that the function never reads, is now followed by
  `(void)name;`, as a guard's binding already is.
