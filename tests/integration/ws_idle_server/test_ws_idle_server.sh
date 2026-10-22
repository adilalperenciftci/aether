#!/bin/sh
# Regression (#3118): std.http's server keeps an upgraded WebSocket open
# while it is quiet.
#
# Every HTTP connection carries a receive timeout, the keep-alive idle one
# (30 s by default), which guards the wait for the next request. After the
# upgrade the handler's blocking ws_recv waited with it still on, took the
# timeout for a close and returned -1: any client quiet that long was
# dropped. The server clears it once the handshake has gone out. Here the
# idle timeout is 1 s and the client is quiet for 2.5 s between messages.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$ROOT/tests/lib/wait_port.sh"
. "$ROOT/tests/lib/server_jobs.sh"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] ws_idle_server: ae not built"; exit 0; }

TMP="$(mktemp -d)"
SRV_PID=""
cleanup() {
    stop_server "$SRV_PID"
    rm -rf "$TMP" || :
    return 0
}
trap cleanup EXIT
fail() { echo "  [FAIL] ws_idle_server: $1"; exit 1; }

if command -v timeout >/dev/null 2>&1; then
    TIMEOUT="timeout 30"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT="gtimeout 30"
else
    TIMEOUT=""
fi

"$AE" build "$SCRIPT_DIR/wsserver.ae" -o "$TMP/wssrv" >"$TMP/b1.log" 2>&1 \
    || { sed -n '1,10p' "$TMP/b1.log"; fail "server did not build"; }
"$AE" build "$SCRIPT_DIR/wsclient.ae" -o "$TMP/wscli" >"$TMP/b2.log" 2>&1 \
    || { sed -n '1,10p' "$TMP/b2.log"; fail "client did not build"; }

"$TMP/wssrv" > "$TMP/srv.log" 2>&1 &
SRV_PID=$!

i=0
while [ "$i" -lt 60 ]; do
    grep -q READY "$TMP/srv.log" 2>/dev/null && break
    sleep 0.1
    i=$((i + 1))
done
grep -q READY "$TMP/srv.log" 2>/dev/null || {
    sed -n '1,10p' "$TMP/srv.log"
    fail "the echo server never became READY"
}
PORT=$(read_ready_port "$TMP/srv.log") || exit 1

OUT=$(AE_TEST_PORT="$PORT" $TIMEOUT "$TMP/wscli" 2>&1) || {
    echo "$OUT" | sed 's/^/         /'
    sed 's/^/         server: /' "$TMP/srv.log"
    fail "the client exited non-zero"
}
case "$OUT" in
    *"PASS: ws idle round-trip"*) ;;
    *) echo "$OUT" | sed 's/^/         /'; fail "the round-trips did not report PASS" ;;
esac

echo "  [PASS] ws_idle_server: an upgraded WebSocket outlives the 1 s idle timeout"
