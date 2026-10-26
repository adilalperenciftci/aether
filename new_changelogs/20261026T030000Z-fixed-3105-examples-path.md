- **examples/ is a path that teaches Aether, and CI checks every step of
  it.** The directory held 119 files in loose groups with nothing saying
  where to start, two styles of the language (`println("...");` and
  `if (x > y)` beside the current style), memory advice the ownership model
  retired ("manual mode is the default", `string.new` and `release` by
  hand) and examples that did not do what their names said; nothing checked
  what any of them printed. `examples/01-language/` is now a numbered tour
  from the first program to ownership, each file one idea in current style,
  starting with what it teaches and how to run it and ending with the exact
  output it prints, and examples/README.md is the path, one row per example
  with a link into the reference. `make check-examples` (an Aether checker,
  tests/examples/check.ae) builds every example, fails on a warning, runs
  each one that ends in an `// Output:` block and compares, requires a
  `// Needs:` line on the ones that cannot run unattended, and checks the
  README links every example (#3105).
