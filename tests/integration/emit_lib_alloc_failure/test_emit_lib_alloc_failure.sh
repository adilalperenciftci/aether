#!/bin/sh
# #2956: an allocation that fails inside a library call ends the call.
#
# Past the memory cap, or with the allocator out of memory, a cap-aware
# allocation returned NULL, the std operation returned its error (a string
# operation, NULL), and the script went on with it: the export returned
# whatever it reached, with AETHER_OK. Now the failure is noted on the call,
# and its next safe point ends it with AETHER_MEMORY_CAP or
# AETHER_OUT_OF_MEMORY and the zero value; its defers run, a `try` in it
# does not catch it, and the library takes the next call.
#
# Fixtures, not tests: alloc.ae is a library; the driver builds it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
CC="${CC:-cc}"
export AETHER_HOME="$ROOT"

[ -x "$AE" ] || { echo "  [SKIP] emit_lib_alloc_failure: $AE not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT
want='cap 0 outcome 4 "the call went past the memory cap" defers 1
guarded 0 outcome 4 defers 2
oom 0 outcome 5 "the call ran out of memory" defers 3
after 160 outcome 0 defers 4'

if ! "$AETHERC" --emit=lib --with=extern "$SCRIPT_DIR/alloc.ae" "$TMP/alloc.c" > "$TMP/alloc.log" 2>&1; then
    echo "  [FAIL] emit_lib_alloc_failure: aetherc --emit=lib failed"
    tail -5 "$TMP/alloc.log" | sed 's/^/        /'
    exit 1
fi
# shellcheck disable=SC2046
if ! "$CC" -O1 -I"$ROOT/include" -I"$ROOT/runtime" $("$AE" cflags --cflags) \
        "$TMP/alloc.c" "$SCRIPT_DIR/host.c" -o "$TMP/host" \
        $("$AE" cflags --libs) > "$TMP/cc.log" 2>&1; then
    echo "  [FAIL] emit_lib_alloc_failure: the host did not build"
    head -10 "$TMP/cc.log" | sed 's/^/        /'
    exit 1
fi
got="$("$TMP/host" 2>"$TMP/host.err" | tr -d '\r')"
if [ "$got" != "$want" ]; then
    echo "  [FAIL] emit_lib_alloc_failure:"
    echo "      got:"; printf '%s\n' "$got" | sed 's/^/        /'
    echo "      want:"; printf '%s\n' "$want" | sed 's/^/        /'
    head -5 "$TMP/host.err" | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] emit_lib_alloc_failure: a call past the memory cap ends with AETHER_MEMORY_CAP, one whose allocator runs out with AETHER_OUT_OF_MEMORY, the zero value and its defers run, a try does not catch it; the next call works"
