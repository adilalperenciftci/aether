- **`ae build --target=wasm` links the runtime again.** The Emscripten build
  compiled a runtime list `ae` kept for itself, which had drifted from
  `runtime/coop_runtime_sources.txt`, the list ci-wasm and the ESP32 build
  read: it lacked `aether_resource_caps.c`, which every string release
  calls, and `aether_exec.c`, `aether_host.c`, `aether_locale_num.c`,
  `aether_supervision.c`, `capsicum_autosandbox.c` and the alloc,
  http_park, quote and udp modules, so a program did not link. `ae` now
  reads that file (installed with the runtime), so the lists cannot drift.
  The file gains the C of `std.floatarr`, `std.strarr` and the StringList of
  `std.collections`, which a program reaches from Aether as it reaches
  `std.intarr` and `std.longarr`. ci-wasm builds a program with `ae build
  --target=wasm` and runs it, and the release layout check asserts the
  file ships (#3383).
