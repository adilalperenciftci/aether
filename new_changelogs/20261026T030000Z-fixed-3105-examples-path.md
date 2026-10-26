- **examples/ is a path that teaches Aether, and CI checks every step of
  it.** The directory held 119 files in loose groups with nothing saying
  where to start, two styles of the language (`println("...");` and
  `if (x > y)` beside the current style), memory advice the ownership model
  retired ("manual mode is the default", `string.new` and `release` by
  hand), examples that did not do what their names said, a stray
  executable, and a sandbox demo whose child could never find the sandbox
  library. Nothing checked what any of them printed. It is seven numbered
  sections now: the language, actors, the standard library, C and other
  languages, containing code, the tools, and whole programs. Each file is
  one idea in current style, starts with what it teaches and how to run it,
  and ends with the exact output it prints, and examples/README.md is the
  path, one row per example with a link into the reference. `make
  check-examples` (an Aether checker, tests/examples/check.ae) runs in
  `make ci` in place of the old build-only step, and `make examples` is it
  (under cmd.exe, `make examples` builds them with `ae examples`, as it did).
  It builds every example, as many at once as the machine has cores, fails
  on a warning (coded or not), type-checks
  the ones that import a contrib bridge, and runs each one that ends in an
  `// Output:` block, with the tree's own `ae` first on PATH, and compares
  what it prints. It also requires a `// Needs:` line on the ones that
  cannot run unattended, and checks that the README links every example and
  the directory holds only source. `ae examples` follows the same headers:
  it builds the programs and skips what is run another way, and it names
  each output by its path, so two `main.ae` files no longer overwrite each
  other (#3105).
