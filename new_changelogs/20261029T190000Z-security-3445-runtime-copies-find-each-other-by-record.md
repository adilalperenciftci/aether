- **A library's code inside a program's deny-all block is held to it, however
  the program was linked (#3445).** Runtime copies share the sandbox levels
  and the execution accounts through the first loaded image that has them,
  and an image said so only by its exports. A Windows executable exports
  nothing, nor does one linked without `-rdynamic` on Linux (a C host linked
  with `ae cflags --libs`), so a program whose copy looked first, before it
  loaded a library with a runtime of its own, kept levels and accounts the
  library's copy never found: the library's code that the program called
  inside a deny-all block was allowed everything, and an account the
  program had put in use was charged nothing the library allocated. Each
  copy now carries a record in its image (a PE section, an ELF note, a
  Mach-O section) that every copy reads in load order, the program first.
  A library built by an earlier release has no record and is still found by
  its export, so with a program that exports nothing it stays apart, as
  before: rebuild it, or build it with `--shared-runtime`.
