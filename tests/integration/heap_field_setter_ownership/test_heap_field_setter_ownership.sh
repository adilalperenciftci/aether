#!/bin/sh
# A struct string field is owned the same way however it was assigned (#1866).
#
# The ownership wrapper only fired for an assignment written against a local
# heap-box pointer. A setter assigns through a pointer PARAMETER, so its store
# was a bare one and the box's destructor released nothing. There was
# therefore no correct way to write a destructor: freeing the field by hand
# double-frees in the local case and leaks in the setter case.
#
# Running to completion is half the assertion (a double free aborts); the
# program checks its own heap growth where the heap count is exact.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

if ! "$AE" build "$SCRIPT_DIR/prog.ae" -o "$TMP/prog" > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] heap_field_setter_ownership: build failed"
    sed 's/^/        /' "$TMP/build.log" | head -8
    exit 1
fi

if ! "$TMP/prog" > "$TMP/out.txt" 2>&1; then
    echo "  [FAIL] heap_field_setter_ownership: program aborted (double free?)"
    sed 's/^/        /' "$TMP/out.txt" | head -6
    exit 1
fi
grep -q "^both freed$" "$TMP/out.txt" || {
    echo "  [FAIL] heap_field_setter_ownership: program did not run to completion"
    sed 's/^/        /' "$TMP/out.txt" | head -6
    exit 1
}

# Freed exactly once, where a leak checker is available: leaks(1) on macOS,
# where the heap count is not exact and the program cannot measure itself.
if [ "$(uname -s)" = Darwin ] && command -v leaks >/dev/null 2>&1; then
    if ! MallocStackLogging=1 leaks --atExit -- "$TMP/prog" > "$TMP/prog".leaks 2>&1; then
        if grep -qE "[1-9][0-9]* leak(s)? for" "$TMP/prog".leaks; then
            echo "  [FAIL] heap_field_setter_ownership: a string leaked"
            grep -E "leaks? for" "$TMP/prog".leaks | sed 's/^/        /' | head -3
            exit 1
        fi
    fi
fi

echo "  [PASS] heap_field_setter_ownership: a field assigned through a setter is owned like one assigned on a local"
