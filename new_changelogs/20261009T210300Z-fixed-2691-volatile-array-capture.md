- **A closure capturing an array a `try` body writes compiles without
  warnings.** Such an array has volatile elements so its stores survive a
  panic (#2618). The closure copied it with `memcpy`, and on the non-GCC
  path (MSVC, emscripten) its constructor `_aether_make_closure_N` took it
  as a plain pointer, both of which discard the qualifier: GCC, clang and
  MSVC warned, and a `-Werror` build failed. The copy now reads each
  element, and the constructor takes a pointer to const volatile elements,
  which a plain array converts to as well. Copying such an array into
  another (`b = a`, `int[2] c = a`) and zeroing what a shorter literal
  stored into it leaves went through `memmove`, `memcpy` and `memset` the
  same way, and no longer warn (#2691).
