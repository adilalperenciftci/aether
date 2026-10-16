- **A binary import the program and the library cannot both free is
  refused, not run into an accounting abort.** A library built the default
  way carries its own copy of the runtime, and on macOS and Windows that copy
  stays apart from the program's: neither may free what the other made. A
  struct holding a string (returned by value, or reached through a typed
  pointer) and a builder that uses its config crossed anyway, and the program
  aborted with "alloc/free accounting underflow" (#2861). `ae` now refuses
  such an import with an error naming each export and the rebuild,
  `ae build --emit=lib --shared-runtime`. Linux and FreeBSD, where ELF
  interposition merges the two copies, and the shared runtime are unaffected.
