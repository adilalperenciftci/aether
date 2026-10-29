- **Generated C compiles with `clang -Wall -Werror` again when it allocates
  nothing.** The two allocation helpers every program's C defines
  (`_aether_alloc` and `_aether_alloc_or_null`, #3377) were plain
  `static inline` functions, and clang warns of an unused one in a `.c` file
  (gcc does not). They now carry `AETHER_MAYBE_UNUSED`, as the prologue's
  other helpers do, defined before them (#3425).
