#!/bin/sh
# The end of main waits for the messages sent, not for an armed receive
# timeout (#3219); wait_for_idle() still does. See watchdog.ae.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

fail() { echo "  [FAIL] exit_armed_timeout: $1"; exit 1; }

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] exit_armed_timeout: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$ROOT/tests/lib/sweep_timeout.sh"
# Well under the watchdog's 30 s: a program that waits for it is stopped.
sweep_timeout_bound TO "$ROOT" 15

AETHER_HOME="$ROOT" "$AE" build "$SCRIPT_DIR/watchdog.ae" -o "$TMP/watchdog" >"$TMP/build.log" 2>&1 \
    || { cat "$TMP/build.log"; fail "the program did not build"; }
OUT="$($TO "$TMP/watchdog" 2>&1)"
RC=$?
[ "$RC" -eq 0 ] || { printf '%s\n' "$OUT"; fail "exit $RC (124 is the 15 s limit: the end of main waited for the watchdog)"; }
WANT="short: ping
short: quiet for 200 ms
main: done"
[ "$OUT" = "$WANT" ] || { printf '%s\n' "$OUT"; fail "the output is not what wait_for_idle and the end of main give"; }

echo "  [PASS] exit_armed_timeout: wait_for_idle fires a countdown, the end of main does not wait for one"
