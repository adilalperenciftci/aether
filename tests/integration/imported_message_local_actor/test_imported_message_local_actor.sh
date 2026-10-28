#!/bin/sh
# Issue #3341: an actor of the program handles a message an imported module
# exports, both through the module's function and sent directly. The module
# merge puts imported declarations before main, after the program's actors,
# and codegen gave a message its id only when it reached it, so the actor's
# arm had no handler and the C did not compile. Messages are now emitted
# ahead of every actor and function.
#
# Acceptance: builds without a warning, runs, prints "total 42".

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
NAME=imported_message_local_actor

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }

out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run main.ae 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "  [FAIL] $NAME: the program did not build or run (rc=$rc)"
    echo "$out" | head -20 | sed 's/^/          /'
    exit 1
fi
if printf '%s\n' "$out" | grep -qi 'warning'; then
    echo "  [FAIL] $NAME: the build warned"
    echo "$out" | head -20 | sed 's/^/          /'
    exit 1
fi
if ! printf '%s\n' "$out" | grep -qx 'total 42'; then
    echo "  [FAIL] $NAME: expected 'total 42'"
    echo "$out" | head -20 | sed 's/^/          /'
    exit 1
fi
echo "  [PASS] $NAME: the program's actor handles an imported module's message"
exit 0
