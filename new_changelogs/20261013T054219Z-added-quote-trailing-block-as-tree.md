- **`quote`: a trailing block handed to the function as a tree.**
  `f(args) quote | a: T | { body }` (also `quote | a: T | -> expr`,
  `quote { body }`, `quote -> expr`) is a fourth trailing-block form beside
  the immediate block, the closure and `callback`. The block is
  type-checked as Aether but never runs: the function, whose last
  parameter is a `quote.Tree`, receives a tree describing it, every node
  carrying the type the checker gave it (a `vec2` declared
  `distinct f32x4` stays `vec2`), each call recorded with its name as
  written rather than made, and each enclosing variable the block reads a
  capture whose cell is the variable itself, so a change the program makes
  after the tree is built is seen through it (a program-level `var` is a
  capture too, its cell the global itself). That is what a shader
  library needs to write GLSL with its uniforms found for it, and what a
  query builder or a test library that prints the failing expression
  needs. The new `std.quote` module reads the tree (kinds, accessors,
  `children` and a pre-order `walk` taking a closure,
  typed capture getters that panic naming both types on a mismatch, a
  printer back to Aether source, a typed dump, a hash of the tree's shape
  for caching). `quote` is not a keyword: it quotes only straight after a
  call's `)` on the same line. Version 1 of the tree holds a subset of
  Aether; the rest is rejected at its line, naming the construct (E0800),
  as are an untyped quote parameter (E0801), a quote given where no
  `quote.Tree` is taken or a closure where one is (E0802), and a write to
  or the address of a captured variable (E0803). See docs/quote.md.
