- **A `size_t` the runtime takes is declared `size_t`, and the call works
  where `size_t` is 32 bits.** `string_new_with_length`, in the generated
  prelude and in eleven std and contrib modules, and std.alloc's and
  std.arena's sizes were declared `long`, which is int64_t. On wasm32 the
  linker swapped each call for a stub that traps, so the first actor
  message that carried a string killed the program under Emscripten
  (`RuntimeError: unreachable`). `make check-extern-widths` had taken a
  size_t for 64 bits; it counts one as pointer-sized now, and also finds a
  C function two shared directories define: contrib.parsers.xml_expat's
  parser is made and freed by `xml_expat_new` and `xml_expat_free`, since
  std.xml defines `xml_parser_new` and `xml_parser_free`. The WebAssembly
  leg fails on a linker warning (#3185).
