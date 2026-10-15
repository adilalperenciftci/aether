#!/bin/sh
# A plain `defer` runs on every exit of its scope, a caught panic's too
# (#2923): the deferred statements a panic leaves run newest first, across
# frames, over the locals as they are then, and leaks(1) finds nothing on
# macOS.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! "$AE" build "$SCRIPT_DIR/prog.ae" -o "$TMP/prog" > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] defer_on_panic: build failed"
    sed 's/^/        /' "$TMP/build.log" | head -8
    exit 1
fi
if ! out="$("$TMP/prog" 2>&1)"; then
    echo "  [FAIL] defer_on_panic: the program failed: $out"
    exit 1
fi
if [ "$out" != "ok 23 700" ]; then
    echo "  [FAIL] defer_on_panic: printed '$out', not 'ok 23 700'"
    exit 1
fi
if [ "$(uname -s)" = Darwin ] && command -v leaks >/dev/null 2>&1; then
    if ! leaks --atExit -- "$TMP/prog" > "$TMP/leaks.out" 2>&1; then
        if grep -qE "[1-9][0-9]* leaks? for" "$TMP/leaks.out"; then
            echo "  [FAIL] defer_on_panic: a value leaked"
            grep -E "leaks? for" "$TMP/leaks.out" | sed 's/^/        /' | head -3
            exit 1
        fi
    fi
fi
echo "  [PASS] defer_on_panic: a caught panic runs the defers it leaves, newest first"
