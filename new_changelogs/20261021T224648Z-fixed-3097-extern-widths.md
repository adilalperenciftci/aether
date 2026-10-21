- **Every extern agrees with its C definition on the width of each argument
  and result, and `make check-extern-widths` keeps it so.** An extern's C
  prototype is written by the compiler and never seen beside the C that
  defines the function, so where the two disagreed the call went ahead with
  the wrong width. The new check, in Aether, found 55 externs that
  disagreed with their C (#3097):
  - C functions declared with a plain `long`, 32 bits on Windows: the Lua
    host's integers, `std.tracking`'s byte count and `std.observe`'s
    tokens were cut to 32 bits there. They are `int64_t` now.
  - Sizes and tokens that are `size_t` or `uint64_t` in C but were
    declared `int`: `string_new_with_length` in 11 modules and in the
    compiler's own prelude, `std.alloc` and `std.arena` sizes, and every
    contrib host's `*_run_sandboxed_with_map` map token. They are `long`
    now. `arena.used` and `arena.size` return `long`.
  - A `char` parameter (`tinygo_call_dynamic`) and `std.casper`'s uid,
    both now as the extern reads them.

  The check runs in CI. A C `long` in a bound signature fails it, since no
  Aether type has that width on every platform. The Lua host also pushes a
  negative whole Double as an integer now; it used to go out as a string.
