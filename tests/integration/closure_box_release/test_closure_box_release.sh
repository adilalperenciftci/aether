#!/bin/sh
# A closure kept in a `ptr` slot is boxed with a reference of its own,
# given back with `release_closure` (#2926); a borrowing `ptr` parameter
# gets a box on the caller's stack. The values are right, the heap does not
# grow where the count is exact, and leaks(1) finds nothing on macOS.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! "$AE" build "$SCRIPT_DIR/prog.ae" -o "$TMP/prog" > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] closure_box_release: build failed"
    sed 's/^/        /' "$TMP/build.log" | head -8
    exit 1
fi
if ! out="$("$TMP/prog" 2>&1)"; then
    echo "  [FAIL] closure_box_release: the program failed: $out"
    exit 1
fi
if [ "$out" != "ok" ]; then
    echo "  [FAIL] closure_box_release: printed '$out', not 'ok'"
    exit 1
fi
if [ "$(uname -s)" = Darwin ] && command -v leaks >/dev/null 2>&1; then
    if ! leaks --atExit -- "$TMP/prog" > "$TMP/leaks.out" 2>&1; then
        if grep -qE "[1-9][0-9]* leaks? for" "$TMP/leaks.out"; then
            echo "  [FAIL] closure_box_release: a value leaked"
            grep -E "leaks? for" "$TMP/leaks.out" | sed 's/^/        /' | head -3
            exit 1
        fi
    fi
fi
echo "  [PASS] closure_box_release: boxes in ptr slots are given back; borrowed ones live on the stack"
