- **A binary import is checked as a source import is.** An `--emit=lib`
  library's catalog wrote each export's source signature without its
  parameters' `@keep`, so a program importing the library as a binary
  passed a borrowed `ptr`, or a string without `string.keep`, to a
  parameter the library keeps, and nothing refused it; the library then
  held a pointer its owner freed. The signature now spells `@keep` and
  `@into` (and is written whenever a parameter has one), the extern `ae`
  declares from it takes them as they are, and such calls are E0902 as in a
  source import. An extern's parameter accepts `@keep` for this. `ae check`
  resolves a binary import too: it refused one as unresolved, where `ae
  build` and `ae run` found the library. A call through a module's
  qualified name (`mod.f(...)`) to that module's `@extern` is checked
  against its `@retain`, `@keep` and `@into` parameters, which only an
  unqualified call was (#3013).
