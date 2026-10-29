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
  copy now carries a record in its image that every copy reads in load
  order, the program first: on ELF a read-only note naming the copy's
  rendezvous by an offset fixed at link time, on PE and Mach-O a section of
  its own. An image is read while it is held loaded, and a record counts
  only when what it names lies inside its image. The record never changes,
  so copies of later releases read it too.
