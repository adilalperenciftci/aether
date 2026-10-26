#!/bin/sh
# A module function keeps a C name no extern of the build binds (#3187).
#
# A function `name` of module `ns` is the C function `ns_name`. When an
# extern binds that C symbol, through the module's own
# `@extern("ns_name") other(...)` or as another module's bare
# `extern ns_name(...)`, the generated C declared one function twice, with
# two types, and did not compile. Here tally's `count` meets its own
# @extern of tally_count and its `total` meets tally_c's extern
# tally_total; both must build, and each call must reach its own function.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
NAME=module_fn_c_symbol

[ -x "$AE" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT
cd "$SCRIPT_DIR" || exit 1

if ! AETHER_LIB_DIR="$SCRIPT_DIR/lib" "$AE" build probe.ae -o "$TMP/probe" >"$TMP/build.log" 2>&1; then
    echo "  [FAIL] $NAME: the probe did not build"
    sed 's/^/        /' "$TMP/build.log" | head -16
    exit 1
fi
if ! "$TMP/probe" >"$TMP/run.log" 2>&1; then
    echo "  [FAIL] $NAME: the probe exited non-zero"
    sed 's/^/        /' "$TMP/run.log" | head -10
    exit 1
fi
want='count 4
total 3
raw 104'
got="$(tr -d '\r' <"$TMP/run.log")"
if [ "$got" != "$want" ]; then
    echo "  [FAIL] $NAME: expected"
    echo "$want" | sed 's/^/        /'
    echo "      got"
    echo "$got" | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] $NAME: module functions and the externs binding their C names both build and run"
exit 0
