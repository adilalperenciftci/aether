- **A string holding a literal reaches an Aether function's `ptr`
  parameter as its characters.** Since 0.818.0 every literal is a pinned
  counted string, and a literal used as a `ptr` is meant to stay its C
  characters wherever it goes. One written straight into the call was, but
  a local, parameter or field holding it (`s = "constructor"`, then
  `take(s)` with `take(p: ptr)`) passed the pinned string's header, so C
  reading the `ptr` read the header's bytes (`strlen` gave 9, not 11). A
  pinned string passed to an Aether function's `ptr` parameter is now its
  characters, as #2967 made it for a `-> ptr` return; a counted string is
  still passed as itself, and an `@aether` C parameter still gets the
  string as Aether holds it. Found by mquickjs-ae's generator.
