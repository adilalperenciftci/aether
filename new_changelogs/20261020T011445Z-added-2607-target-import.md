- **One binary, both widths: `@target("avx2") import m as alias` (#2607).**
  A build picked one width for every `f32x8` in the program: one register
  under `-mavx2`, which faults on a CPU without AVX2, or two halves
  everywhere. A module imported at `@target("avx2")` is now a second copy of
  it, with its own functions and variables, compiled for AVX2 while the rest
  of the program keeps the build's flags, and `lanes.cpu_has_avx2()` chooses
  between the two at run time (`lanes.native8()` says which form the calling
  code has). Both copies compute the same bits. An eight-lane value passed
  between the copies, a closure inside the copy, an import without an alias
  and an unknown target are compile errors. Off GCC and Clang on x86, and on
  the `AETHER_GCC_COMPAT=0` path, the copy is plain code with no target
  attribute.
