- **A library whose runtime is left to its host loads where there is none
  yet.** The allocation helpers of a `--emit=lib` library read the runtime's
  test-hook flag, and its loop heads the safe point's, both data, which the
  dynamic loader binds when the library is loaded: a library linked with a
  raw `cc -shared` did not load at all without a runtime, so `ae lib-info`
  could not read the catalog of one whose closures allocate. On ELF and
  Mach-O those references are now weak, as the callback registry's was, and
  an absent flag reads as unarmed (#3455).
