- **In a source tree, editing a runtime header invalidates `ae`'s build
  cache.** The key covered the compiler, the driver and `libaether.a`, but
  not the headers under `runtime/` and `std/` that generated C includes, so
  after a header edit and `make`, `ae run` served the binary built against
  the old header and a test reported the old code's result. Those headers'
  content is now part of the key whenever `ae` runs from a source tree; an
  installed toolchain's headers change only with an upgrade, which changes
  the compiler too (#2707).
