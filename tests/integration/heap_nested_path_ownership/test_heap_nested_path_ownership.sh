#!/bin/sh
# A struct string field is owned the same way however the path is spelled (#1879).
#
# Follow-up to #1866. That fixed the setter-through-a-parameter case; a NESTED
# path (`o.inner.name = ...`) still emitted a bare store with no
# `_heap_<field>` tracker, so the inner struct's destructor believed it owned
# nothing and the string leaked -- while the identical write on the inner
# pointer released correctly. Ownership followed how the assignment was
# SPELLED rather than the type, which the reporter reached through the
# ordinary shape of a model holding a material holding a texture path.
#
# Running to completion is half the assertion (a double free aborts). The
# program checks its own heap growth where the count is exact, and valgrind
# checks for a definite leak where it is installed.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

if ! "$AE" build "$SCRIPT_DIR/prog.ae" -o "$TMP/prog" > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] heap_nested_path_ownership: build failed"
    sed 's/^/        /' "$TMP/build.log" | head -8
    exit 1
fi

if ! "$TMP/prog" > "$TMP/out.txt" 2>&1; then
    echo "  [FAIL] heap_nested_path_ownership: program aborted (double free?)"
    sed 's/^/        /' "$TMP/out.txt" | head -6
    exit 1
fi
grep -q "^all freed$" "$TMP/out.txt" || {
    echo "  [FAIL] heap_nested_path_ownership: program did not run to completion"
    sed 's/^/        /' "$TMP/out.txt" | head -6
    exit 1
}

# Where a leak checker exists, assert the actual property rather than only the
# generated text -- the tracker could be set and still not be read at free.
if command -v valgrind >/dev/null 2>&1; then
    if ! valgrind --error-exitcode=9 --leak-check=full --errors-for-leak-kinds=definite \
            "$TMP/prog" > "$TMP/vg.txt" 2>&1; then
        echo "  [FAIL] heap_nested_path_ownership: valgrind reported a definite leak"
        grep -E "definitely lost|Invalid" "$TMP/vg.txt" | sed 's/^/        /' | head -6
        exit 1
    fi
fi

echo "  [PASS] heap_nested_path_ownership: a field assigned through a nested path is owned like a direct one"
