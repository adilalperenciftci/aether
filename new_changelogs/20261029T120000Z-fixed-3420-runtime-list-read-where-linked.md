- **`ae build --target=wasm` and `ae check` no longer need the native
  runtime list.** `ae` read MANIFEST, the list of runtime sources a build
  without libaether.a compiles, as soon as it found the toolchain, for every
  command, and exited when it could not. Only a native link reads it: a wasm
  build compiles `runtime/coop_runtime_sources.txt`, and a check compiles no
  runtime. So in a tree `make compiler ae` built, or an install without
  libaether.a and MANIFEST, a wasm build stopped before emcc. The list is now
  read where a native link needs it, with the same message when it cannot
  be (#3420).
