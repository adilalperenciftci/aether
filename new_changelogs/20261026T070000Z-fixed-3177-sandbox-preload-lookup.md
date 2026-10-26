- **`spawn_sandboxed` finds its preload library from any program.**
  `libaether_sandbox.so` was looked for only beside the running program
  and in `../build/` from it. So a program `ae run` built (it lives in the
  build cache) or one an installed toolchain built never found it, and
  `spawn_sandboxed` printed "cannot find libaether_sandbox.so" and started
  no child. No install shipped the library at all. The lookup is now one,
  shared by `spawn_sandboxed` and the contrib process hosts:
  `AETHER_SANDBOX_PRELOAD`, beside the program, then `lib/aether/`, `lib/`
  and `build/` under `AETHER_HOME` (which `ae` sets for every program it
  runs) and under the program's directory's parent. When none has it, the
  message names every place looked at. `install.sh`, `make install` and
  the release archives install the library. It has a make rule of its
  own, so an edit to its source or a deleted library rebuilds it (#3177).
