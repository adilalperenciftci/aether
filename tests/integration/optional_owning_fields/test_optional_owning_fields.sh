#!/bin/sh
# An optional struct field owns what it holds (#2822, #2921): its values are
# right through literals, stores, a copy and `none`, the heap does not grow
# where the count is exact, and leaks(1) finds nothing on macOS.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

if ! "$AE" build "$SCRIPT_DIR/prog.ae" -o "$TMP/prog" > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] optional_owning_fields: build failed"
    sed 's/^/        /' "$TMP/build.log" | head -8
    exit 1
fi
if ! out="$("$TMP/prog" 2>&1)"; then
    echo "  [FAIL] optional_owning_fields: the program failed: $out"
    exit 1
fi
want="w#label2 - w#owner2 w#1 w#t 3"
if [ "$out" != "$want" ]; then
    echo "  [FAIL] optional_owning_fields: printed '$out', not '$want'"
    exit 1
fi
if [ "$(uname -s)" = Darwin ] && command -v leaks >/dev/null 2>&1; then
    if ! MallocStackLogging=1 leaks --atExit -- "$TMP/prog" > "$TMP/leaks.out" 2>&1; then
        if grep -qE "[1-9][0-9]* leak(s)? for" "$TMP/leaks.out"; then
            echo "  [FAIL] optional_owning_fields: a value leaked"
            grep -E "leaks? for" "$TMP/leaks.out" | sed 's/^/        /' | head -3
            exit 1
        fi
    fi
fi
echo "  [PASS] optional_owning_fields: an optional field takes, releases and copies what it holds"
