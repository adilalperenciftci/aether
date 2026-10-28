#!/bin/sh
# #3383: `ae build --target=wasm` links the runtime runtime/coop_runtime_sources.txt
# lists, the one list ci-wasm and the ESP32 build read.
#
# ae kept a list of its own in tools/ae.c, which drifted from that file: it
# lacked aether_resource_caps.c (every string release calls aether_caps_free),
# aether_exec.c, aether_host.c, aether_locale_num.c, aether_supervision.c,
# capsicum_autosandbox.c and the alloc, http_park, quote and udp modules, so a
# program built for the Emscripten target did not link. ae now reads the file.
#
# emcc is NOT required: a stub on PATH answers --version and prints every .c
# file it was handed, and the test compares them with the file's list.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
export AETHER_HOME="$ROOT"

[ -x "$AE" ] || { echo "  [SKIP] wasm_runtime_sources: $AE not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT
mkdir -p "$TMP/bin"
if ! "${CC:-cc}" "$SCRIPT_DIR/emcc_record.c" -o "$TMP/bin/emcc" > "$TMP/stub.log" 2>&1; then
    echo "  [FAIL] wasm_runtime_sources: could not compile emcc_record.c"
    head -5 "$TMP/stub.log" | sed 's/^/        /'
    exit 1
fi
printf 'main() {\n    println("hi")\n}\n' > "$TMP/hi.ae"
(cd "$TMP" && PATH="$TMP/bin:$PATH" "$AE" build --target=wasm hi.ae -o "$TMP/hi") > "$TMP/out.txt" 2>&1

# The runtime files emcc was handed, as paths from the repository root: each
# argument cut to the part from its runtime/ or std/ directory on.
grep '^SRC ' "$TMP/out.txt" | sed 's/^SRC //' | tr '\\' '/' | tr -d '\r' |
    sed -n -e 's#^.*/runtime/#runtime/#p' -e 's#^.*/std/#std/#p' | sort > "$TMP/got.txt"
sed -e '/^#/d' -e '/^[[:space:]]*$/d' "$ROOT/runtime/coop_runtime_sources.txt" | tr -d '\r' | sort > "$TMP/want.txt"
if [ ! -s "$TMP/got.txt" ]; then
    echo "  [FAIL] wasm_runtime_sources: the wasm build never reached emcc"
    tail -8 "$TMP/out.txt" | sed 's/^/        /'
    exit 1
fi
if [ "$(cat "$TMP/got.txt")" != "$(cat "$TMP/want.txt")" ]; then
    echo "  [FAIL] wasm_runtime_sources: emcc was not handed the runtime/coop_runtime_sources.txt list"
    echo "      missing from the build:"; grep -vxF -f "$TMP/got.txt" "$TMP/want.txt" | sed 's/^/        /'
    echo "      not in the list:"; grep -vxF -f "$TMP/want.txt" "$TMP/got.txt" | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] wasm_runtime_sources: ae build --target=wasm links the $(wc -l < "$TMP/want.txt" | tr -d ' ') files of runtime/coop_runtime_sources.txt"
