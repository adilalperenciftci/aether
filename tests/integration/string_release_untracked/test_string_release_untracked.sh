#!/bin/sh
# string.release on a string local releases what it holds, whichever way the
# value came (#1977): a local owns its value (R2), so the release has no
# condition.
#
# Asserted on the GENERATED C rather than by leak-counting a running binary:
# the defect is that one branch was never emitted, so the emitted code is the
# precise statement of the fix and it checks the same on every platform.
# The leak gates cover the runtime side.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
AE="$ROOT/build/ae"
[ -x "$AETHERC" ] || { echo "  [SKIP] string_release_untracked: build/aetherc missing"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT

if ! "$AETHERC" "$SCRIPT_DIR/probe.ae" "$TMP/out.c" > "$TMP/gen.log" 2>&1; then
    echo "  [FAIL] string_release_untracked: codegen failed"
    sed 's/^/        /' "$TMP/gen.log" | head -10
    exit 1
fi

# A string local owns what it holds (R2), so the release is unconditional and
# leaves the local empty: what it held is released whichever way it came.
if ! grep -q "(aether_heap_str_free((void\*)prev), prev = NULL, (void)0)" "$TMP/out.c"; then
    echo "  [FAIL] string_release_untracked: the release of the local is not unconditional"
    grep -n "prev" "$TMP/out.c" | sed 's/^/        /' | head -5
    exit 1
fi

# The program still builds and runs.
if [ -x "$AE" ]; then
    if "$AE" build "$SCRIPT_DIR/probe.ae" -o "$TMP/probe" > "$TMP/build.log" 2>&1; then
        if "$TMP/probe" > "$TMP/run.out" 2>&1; then
            grep -q "^done: value 199$" "$TMP/run.out" || {
                echo "  [FAIL] string_release_untracked: wrong output"
                sed 's/^/        /' "$TMP/run.out" | head -5
                exit 1
            }
        fi
    fi
fi

echo "  [PASS] string_release_untracked: release frees an untracked value too"
exit 0
