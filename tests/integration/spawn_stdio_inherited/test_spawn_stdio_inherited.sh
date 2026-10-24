#!/bin/sh
# Regression: os.* spawn paths give the child its parent's standard streams
# even when the parent marked them close-on-exec (Node does). See harness.c.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        echo "  [SKIP] spawn stdio inherited: POSIX fork/exec only"; exit 0 ;;
esac

if [ ! -f "$ROOT/build/libaether.a" ]; then
    echo "  [SKIP] spawn stdio inherited: build/libaether.a not built"
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if ! ${CC:-cc} -o "$tmpdir/harness" "$SCRIPT_DIR/harness.c" \
        "$ROOT/build/libaether.a" -lpthread -lm 2>"$tmpdir/cc.err"; then
    # The runtime links more libraries on some platforms; try the full set.
    if ! ${CC:-cc} -o "$tmpdir/harness" "$SCRIPT_DIR/harness.c" \
            "$ROOT/build/libaether.a" -lpthread -ldl -lm -lz -lssl -lcrypto 2>"$tmpdir/cc.err"; then
        echo "  [FAIL] could not link the harness against libaether.a"
        sed 's/^/          /' "$tmpdir/cc.err" | head -8
        exit 1
    fi
fi

out="$("$tmpdir/harness" "$SCRIPT_DIR/probe.sh" 2>&1 </dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "PASS: the spawned child has stdin, stdout and stderr"; then
    echo "  [PASS] a spawned child has its standard streams although the parent marked them close-on-exec"
    echo "PASS: spawn_stdio_inherited"
    exit 0
fi
echo "  [FAIL] a spawned child lost its standard streams"
printf '%s\n' "$out" | sed 's/^/          /' | head -6
echo "FAIL: spawn_stdio_inherited"
exit 1
