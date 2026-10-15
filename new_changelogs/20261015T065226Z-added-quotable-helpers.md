- **`@quotable` functions: helpers a quote can call (std.quote version 2).**
  A function marked `@quotable` is ordinary Aether whose body is also a tree.
  A quote's call of one is a `HELPER_CALL`, and the quote's tree carries every
  `@quotable` function its body reaches, callees first
  (`quote.helper_count`/`helper`/`helper_named`, each a `quote.Tree` with
  `function_name` and `return_type`), so a back end can write each out as a
  function of its own (ae3d's GLSL). The quote's hash covers each helper it
  reaches, so editing a helper invalidates a cache keyed on the hash. A
  helper's body is checked against the quote subset where it is defined; one
  that reaches itself through `@quotable` calls is E0804 (GLSL and MSL have
  no recursion), and one that reads a variable outside it is E0805.
  `quote.VERSION` is 2, and the format version is in the hash, so **every
  quote's hash changes once**: regenerate anything cached under it (ae3d:
  `build/generate_shaders`).
