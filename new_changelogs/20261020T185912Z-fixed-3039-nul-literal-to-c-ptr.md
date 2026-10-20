- **A string literal holding a NUL goes to a C `ptr` without a warning.**
  `probe_len("a\0bc")` with `extern probe_len(p: ptr) -> int` made gcc warn
  that the call discarded `const` (the literal's bytes are a `static const`
  array beside its pinned string), which failed `-Werror` builds. The
  bytes now go to C typed `char*`, as a C string literal is, every byte
  still there; the pinned string the program holds is unchanged (#3039).
