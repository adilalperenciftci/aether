- **An imported module's unused constants no longer break a `-Wall -Werror`
  build.** Every `const` of every imported module was a file-scope
  `static const` in the generated C whether the program named it or not, so
  `import std.fs` alone gave fourteen unused `ae_const_fs_KIND_*` (since
  0.778.0), each `-Wunused-const-variable`, which `-Wall` turns on for C on
  gcc and clang. The sweep that drops the imported functions nothing reaches
  (#2613) now drops the imported constants nothing names as well, after type
  checking, so they are still checked.
