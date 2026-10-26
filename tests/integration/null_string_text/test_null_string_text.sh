#!/bin/sh
# Regression (#3129): a null string is the empty text wherever it is read as
# text (==, !=, ordering, string.equals, interpolation, println), and
# `s == null` still asks whether there is a string at all. See probe.ae.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -x "$AE" ] || AE="$ROOT/build/ae.exe"

TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT

if ! "$AE" build "$SCRIPT_DIR/probe.ae" -o "$TMPDIR/probe" >"$TMPDIR/build.log" 2>&1; then
    echo "  [FAIL] null_string_text: build failed"
    sed 's/^/    /' "$TMPDIR/build.log" | head -15
    exit 1
fi

"$TMPDIR/probe" >"$TMPDIR/run.log" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "  [FAIL] null_string_text: probe exited $rc"
    sed 's/^/    /' "$TMPDIR/run.log" | head -10
    exit 1
fi

# println of the null string is an empty line, not "(null)".
expected="$(printf '\nok')"
actual="$(tr -d '\r' < "$TMPDIR/run.log")"
if [ "$actual" != "$expected" ]; then
    echo "  [FAIL] null_string_text: println of the null string did not print an empty line"
    sed 's/^/    | /' "$TMPDIR/run.log" | head -6
    exit 1
fi

echo "  [PASS] null_string_text"
