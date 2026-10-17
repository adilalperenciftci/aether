- **Each file's `extern` calls are checked against its own declaration.**
  Every file's bare externs shared one global symbol, so the first
  declaration of a name registered was the one every file's calls were
  checked, and generated, against. A program importing a module that
  declares `extern memcpy(dst: ptr, src: int[], n: long)` failed another
  module's own `memcpy(d, p, 8)` ("expected int[], got a bare ptr"), and
  which declaration won depended on what the program imported and in what
  order (ae3d: ae3d.vkspirv's memcpy broke 119 calls in other modules, and a
  test's `sin`). A file that declares an extern now gets its own
  declaration, in the type checker and in code generation (`@heap`
  adoption, `@retain`); one that calls an extern it does not declare gets
  another file's, as before.
