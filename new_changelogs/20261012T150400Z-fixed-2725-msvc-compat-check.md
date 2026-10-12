- **The C written for non-GCC compilers is checked in CI, by cl.exe itself.**
  `tests/compiler/test_msvc_compat.sh`, which compiles generated C with
  `AETHER_GCC_COMPAT 0` (the path MSVC takes), was run by no target or
  workflow, and needed `python3`, which MSYS2 lacks. It now runs as strict C11
  under gcc on the Linux / GCC leg and under cl.exe in the Windows workflow's
  MSVC job, where the warnings that mean a C type error (an undeclared
  function, a wrong argument type, a dropped qualifier) fail it; it gained a
  closure over arrays a `try` body writes, the case of #2691. `make
  test-msvc-compat` runs it locally (#2725). A string stored into an array
  element is still a GNU statement expression on that path, which cl.exe
  cannot compile (#2765).
