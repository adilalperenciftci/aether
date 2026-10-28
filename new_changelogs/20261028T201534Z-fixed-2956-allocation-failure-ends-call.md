- **An allocation that fails inside a library call ends the call.** Past
  `aether_set_memory_cap`, or with the allocator out of memory, a
  cap-aware allocation returned NULL, the std operation returned its error
  (a string operation, NULL), and the script went on with it: the export
  returned whatever it reached with `AETHER_OK`. A send whose payload copy
  failed, or a captured variable or `make([]T, n)` that could not be
  allocated, stopped the process or panicked as an ordinary panic. Inside
  an export the failure is now noted on the call, which ends at its next
  safe point or its return with `AETHER_MEMORY_CAP` or
  `AETHER_OUT_OF_MEMORY` and the zero value, its defers run and a `try`
  in it not catching it; an allocation the code cannot go on without ends
  the call at once with `AETHER_OUT_OF_MEMORY`, a send's message values
  released. Outside an export nothing changes. Neither reporting nor
  unwinding allocates any more: the allocation journal's drain, which took
  a copy of the entries it released with `malloc` (and skipped them when
  that failed), drains in place, and no longer releases a second time an
  entry a release of the same frame forgot (#2956).
