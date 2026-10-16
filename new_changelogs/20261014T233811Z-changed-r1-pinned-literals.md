- **Every string literal is a counted string, and C gets characters.**
  Stage 2 (R1) of the ownership model: a string literal is a static,
  pinned `AetherString` (retain and release leave it alone), as a literal
  holding a NUL already was (#2520), so every string value the program
  holds has the same shape and releasing one is always right. Where a
  string reaches C it is passed as its characters (R4): an extern's
  `string` or `ptr` parameter, a C-variadic `...` (an extern's or an
  Aether variadic function's, read by `va_arg` or forwarded as a
  `va_list`), and the `getenv` and `atoi` builtins. A C function that
  wants the string itself declares the parameter `@aether`, on a `ptr` as
  on a `string`; std's containers do. A literal used as a `ptr` stays its
  C characters wherever it goes. A fault is its name's pinned string.
  `string.new` and `string.format` read a counted string's bytes, where
  they read its header. C that calls an Aether `-> string` function
  through a pointer reads the result with `aether_string_data`, as
  docs/c-interop.md says of every Aether string.
