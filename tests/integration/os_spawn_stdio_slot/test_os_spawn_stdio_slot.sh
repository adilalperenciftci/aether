#!/bin/sh
# A spawned child keeps only the parent's own standard streams (#3209).
# See probe.ae; the descriptor work is in shim.c.

case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        echo "  [SKIP-WIN] os_spawn_stdio_slot: no fork on Windows"
        exit 0
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ]; then
    echo "  [SKIP] os_spawn_stdio_slot: $AE not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$ROOT/tests/lib/sweep_timeout.sh"
sweep_timeout_bound TO "$ROOT" 60

if ! AETHER_HOME="$ROOT" "$AE" build "$SCRIPT_DIR/probe.ae" -o "$TMP/probe" \
        --extra "$SCRIPT_DIR/shim.c" >"$TMP/build.log" 2>&1; then
    echo "  [FAIL] os_spawn_stdio_slot: build failed"
    sed 's/^/    /' "$TMP/build.log" | head -20
    exit 1
fi

OUT="$($TO "$TMP/probe" 2>&1)"
RC=$?
if [ "$RC" -ne 0 ] || [ "$OUT" != "PASS" ]; then
    echo "  [FAIL] os_spawn_stdio_slot: exit $RC"
    printf '%s\n' "$OUT" | sed 's/^/    /' | head -10
    exit 1
fi
echo "  [PASS] os_spawn_stdio_slot"
