#!/bin/sh
# #2707: in a source tree, the build cache key covers the runtime and std
# headers that generated C includes. Editing one and running `make` left the
# key unchanged, so `ae run` served the binary built against the old header
# and a test reported the old code's result.
#
# A probe header is added under runtime/utils for the duration of the test
# (removed on exit) and changed once; each change has to move the key, and
# removing it has to bring the original key back.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

fail() { echo "  [FAIL] cache_key_runtime_headers: $1"; exit 1; }

if [ ! -f "$ROOT/runtime/actors/aether_panic.h" ]; then
    echo "  [SKIP] cache_key_runtime_headers: not a source tree"
    exit 0
fi

TMP="$(mktemp -d)"
probe="$ROOT/runtime/utils/zz_cache_key_probe_$$.h"
trap 'rm -f "$probe"; rm -rf "$TMP"' EXIT INT TERM
export AETHER_CACHE_DIR="$TMP/cache"
printf 'main() {\n    println("probe")\n}\n' > "$TMP/p.ae"

# The key a build looks up (`[cache] hit|miss: <key>` under -v).
key() {
    "$AE" build -v "$TMP/p.ae" -o "$TMP/p" 2>&1 |
        sed -n 's/^\[cache\] \(hit\|miss\): \([0-9a-f][0-9a-f]*\).*/\2/p' | head -1
}

# A first build writes the depfile later keys are made from.
key > /dev/null
k1="$(key)"
[ -n "$k1" ] || fail "no cache key reported"
[ "$(key)" = "$k1" ] || fail "the key is not stable between two builds"

printf '/* cache key probe */\n' > "$probe"
k2="$(key)"
[ "$k2" != "$k1" ] || fail "adding a runtime header left the key unchanged"

printf '/* cache key probe, edited */\n' > "$probe"
k3="$(key)"
[ "$k3" != "$k2" ] || fail "editing a runtime header left the key unchanged"

rm -f "$probe"
[ "$(key)" = "$k1" ] || fail "removing the header did not bring the key back"

echo "  [PASS] cache_key_runtime_headers: runtime header edits change the build cache key"
