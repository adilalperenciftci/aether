#!/bin/sh
# A string struct field stored from a local frees exactly the reference it
# holds (prog.ae says which shapes, and what they broke). Running to
# completion is half the assertion: a double free, or a free of a literal,
# aborts. The program checks its own heap growth where the count is exact,
# and leaks(1) checks the same on macOS.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -x "$AE" ] || { echo "  [SKIP] heap_field_borrowed_var_no_double_free: build/ae missing"; exit 0; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# 1. It runs to completion — the actual bug was a teardown abort. Build a real
#    binary and run it; a double free / rodata free crashes here.
if ! "$AE" build "$SCRIPT_DIR/prog.ae" -o "$TMP/prog" > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] heap_field_borrowed_var_no_double_free: build failed"
    sed 's/^/        /' "$TMP/build.log" | head -8
    exit 1
fi
if ! "$TMP/prog" > "$TMP/run.out" 2>&1; then
    echo "  [FAIL] heap_field_borrowed_var_no_double_free: program aborted at runtime (rc $?)"
    sed 's/^/        /' "$TMP/run.out" | head -8
    exit 1
fi
if ! grep -q "^done$" "$TMP/run.out"; then
    echo "  [FAIL] heap_field_borrowed_var_no_double_free: did not reach 'done'"
    sed 's/^/        /' "$TMP/run.out" | head -8
    exit 1
fi

# 2. Freed exactly once, where a leak checker is available. leaks(1) is the one
#    that works on macOS; Linux CI covers the same program under Valgrind.
if [ "$(uname -s)" = Darwin ] && command -v leaks >/dev/null 2>&1; then
    if ! MallocStackLogging=1 leaks --atExit -- "$TMP/prog" > "$TMP/leaks.out" 2>&1; then
        if grep -qE "[1-9][0-9]* leak(s)? for" "$TMP/leaks.out"; then
            echo "  [FAIL] heap_field_borrowed_var_no_double_free: the owned value leaked"
            grep -E "leaks? for" "$TMP/leaks.out" | sed 's/^/        /' | head -3
            exit 1
        fi
    fi
fi

echo "  [PASS] heap_field_borrowed_var_no_double_free: each field frees what it holds, once"
exit 0
