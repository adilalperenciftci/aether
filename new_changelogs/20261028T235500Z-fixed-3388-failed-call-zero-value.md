- **A failed call returns its zero value on every path.** A library call
  that ran to its return with a stop noted after its last safe point (an
  allocation it survived, a JSON parse that stopped, the deadline's flag)
  ended with that outcome but returned its real result ("hello7" with
  `AETHER_OUT_OF_MEMORY`), which a host following `libaether.h` (release
  only what an `AETHER_OK` call returned) leaked. The stub now returns the
  zero value and releases what the function returned: a string, or the
  strings and closures of a struct or closure by value. An Aether importer
  of a library with its own runtime gives such a string back to the
  library before it raises the failure, also for a library built before
  this change (#3388).
