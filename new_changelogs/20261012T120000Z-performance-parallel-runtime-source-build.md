- **`ae build --trace`, and any build from a toolchain without libaether.a,
  compiles the runtime in parallel.** Such a source build handed every
  runtime source (about 90) to the one compiler command that links the
  program, which compiled them one after another. They are now compiled to
  objects first, as many at a time as there are processors, and the link
  takes the objects: message_trace's traced build went from 54 s to 17 s on
  an 8-processor Windows machine. A compile that fails, or a compiler that is
  a Windows batch file, falls back to the single command, which reports the
  error as before (#2757).
