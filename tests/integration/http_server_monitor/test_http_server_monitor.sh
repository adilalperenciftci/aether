#!/bin/sh
# The HTTP server's monitor (#3131). The server prints nothing itself; what it
# has to say goes to the monitor the program chose. A foreground server with
# no monitor gets the console one (the banner), null_monitor silences it, and
# a program's own monitor replaces it. A background server, and a failed bind,
# put nothing on stdout: the bind's reason comes back in its error.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

fail() { echo "  [FAIL] http_server_monitor: $1"; exit 1; }

run() { MONITOR_MODE="$1" AETHER_HOME="$ROOT" "$AE" run "$SCRIPT_DIR/$2" 2>&1; }

OUT="$(run - monitor.ae)" || { echo "$OUT"; fail "the monitor program failed"; }
[ "$OUT" = "MONITOR-OK" ] || { echo "$OUT"; fail "a background server or a failed bind printed something"; }

OUT="$(run default foreground.ae)" || { echo "$OUT"; fail "a foreground server failed"; }
echo "$OUT" | grep -q "^Server running at http://127.0.0.1:[0-9]" \
    || { echo "$OUT"; fail "a foreground server with no monitor printed no banner"; }

OUT="$(run null foreground.ae)" || { echo "$OUT"; fail "a server with null_monitor failed"; }
[ "$OUT" = "FG-DONE" ] || { echo "$OUT"; fail "null_monitor did not silence the server"; }

OUT="$(run own foreground.ae)" || { echo "$OUT"; fail "a server with its own monitor failed"; }
EXPECT="OWN listening on 127.0.0.1
OWN stopped
FG-DONE"
[ "$OUT" = "$EXPECT" ] || { echo "$OUT"; fail "the program's monitor did not replace the banner, or its events came out of order"; }

echo "  [PASS] http_server_monitor: the server reports through its monitor, banner by default, silent on request"
