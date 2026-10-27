- **The fork-join benchmarks compile again.** Their kernels handed back a
  borrowed item and one result closure kept a borrowed pointer, both E0902
  since 0.836, and nothing built the programs under `benchmarks/`, so the
  break went unseen. The kernels return `null` (their result was discarded),
  the closure declares its parameter `@keep`, and a test now type-checks
  every benchmark program (#3295).
