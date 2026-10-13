#!/bin/sh
# Regression (#2763 follow-up): a function with a literal or `_` pattern
# parameter hands back the argument at the returned parameter's own
# position.
#
# probe.ae calls `sel(0, g, k)`, which gives `a` (g) to an extern that
# keeps it and returns `b` (k). The returned parameter's position was
# counted over the variable parameters alone, so `g` was taken for the
# argument handed back: its local released it at its scope end while C
# still held it, and fire() called a freed environment (a wrong count or a
# crash). The probe must print "fire 2 use 4 burned 33" and exit 0.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] closure_handback_pattern_extern: toolchain not built"
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cd "$SCRIPT_DIR" || exit 1

build_log="$tmpdir/build.log"
if ! "$AE" build probe.ae -o "$tmpdir/probe" >"$build_log" 2>&1; then
    echo "  [FAIL] closure_handback_pattern_extern: ae build failed"
    sed 's/^/    /' "$build_log" | head -30
    exit 1
fi

run_log="$tmpdir/run.log"
"$tmpdir/probe" >"$run_log" 2>&1
rc=$?

if [ $rc -ne 0 ]; then
    echo "  [FAIL] closure_handback_pattern_extern: probe exited $rc (expect 0)"
    sed 's/^/    /' "$run_log" | head -30
    exit 1
fi

if ! tr -d '\r' < "$run_log" | grep -q "^fire 2 use 4 burned 33$"; then
    echo "  [FAIL] closure_handback_pattern_extern: probe did not print 'fire 2 use 4 burned 33'"
    sed 's/^/    /' "$run_log" | head -10
    exit 1
fi

echo "  [PASS] closure_handback_pattern_extern: the kept argument stays alive"
exit 0
