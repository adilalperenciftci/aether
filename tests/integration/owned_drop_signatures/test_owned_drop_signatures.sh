#!/bin/sh
# Regression (#3413): every drop function the checker accepts for an owned
# type compiles in the unwind journal, and runs once on each path.
#
# The journal entry of an owned place (#3406) passed the type's drop as
# `void (*)(void*)`, so a drop that returns a value, or a C drop whose
# prototype the generated C sees typed (`int fclose(FILE*)`, or handle.h's
# `int handle_close(Handle*)`, force-included through aether.toml), failed to
# compile with "incompatible pointer type". probe.ae holds each in a
# function's local and in a handler's binding, left by a panic and normally,
# and counts the drops (fclose by what it flushed).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] owned_drop_signatures: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT

cd "$SCRIPT_DIR" || exit 1
if ! AETHER_HOME="$ROOT" "$AE" build probe.ae -o "$TMP/probe" >"$TMP/build.log" 2>&1; then
    echo "  [FAIL] owned_drop_signatures: probe.ae did not build"
    grep -E "error|note: expected" "$TMP/build.log" | head -8 | sed 's/^/        /'
    exit 1
fi

# In the scratch directory: the probe writes its files where it runs.
cd "$TMP" || exit 1
if ! ./probe >"$TMP/run.log" 2>&1 || ! grep -q "^All PASS" "$TMP/run.log"; then
    echo "  [FAIL] owned_drop_signatures: the probe failed"
    grep -E "FAIL|panic" "$TMP/run.log" | head -12 | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] owned_drop_signatures: a drop with a result, a typed C drop and fclose, in a local and an arm's binding, ran once each on a panic and on the normal path"
