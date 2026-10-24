#!/bin/sh
# A proxy whose upstream cannot be reached owes its client an answer: 502, with
# X-Aether-Proxy-Error: upstream_transport, as the blocking path gives. The
# event-driven path used to close the client's connection with nothing written
# when the dial failed (or the send, or the read), which a client sees as
# "Empty reply from server" (curl exit 52) and a load balancer in front of a
# pool with nothing behind it as a hang-up instead of a gateway error.
#
# The upstream here is nothing at all: port 1 is where nothing listens, so the
# dial is refused. A second request on the same client connection must be
# answered too (the connection may be kept or closed, but not left silent).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if ! command -v curl >/dev/null 2>&1; then
    echo "  [SKIP] curl not on PATH"
    exit 0
fi

. "$ROOT/tests/lib/wait_port.sh"
. "$ROOT/tests/lib/server_jobs.sh"

TMPDIR="$(mktemp -d)"
PX_PID=""
cleanup() {
    stop_server "$PX_PID"
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# The reverse-proxy suite's driver, not a copy (see http_proxy_stale_pooled_connection).
SERVER_SRC="$SCRIPT_DIR/../http_reverse_proxy/server.ae"
if ! AETHER_HOME="$ROOT" "$AE" build "$SERVER_SRC" -o "$TMPDIR/server" >"$TMPDIR/build.log" 2>&1; then
    echo "  [FAIL] build:"; head -30 "$TMPDIR/build.log"; exit 1
fi

AETHER_HOME="$ROOT" "$TMPDIR/server" proxy 1 >"$TMPDIR/px.log" 2>&1 &
PX_PID=$!
deadline=$(($(date +%s) + 15))
while ! grep -q '^READY ' "$TMPDIR/px.log" 2>/dev/null; do
    kill -0 "$PX_PID" 2>/dev/null || { echo "  [FAIL] proxy died:"; head -20 "$TMPDIR/px.log"; exit 1; }
    [ "$(date +%s)" -lt "$deadline" ] || { echo "  [FAIL] proxy never READY"; exit 1; }
    sleep 0.05
done
PX_PORT=$(read_ready_port "$TMPDIR/px.log") || exit 1
wait_port "$PX_PORT" || exit 1

# One request: the status and the error header, within the time it takes to be refused.
RESP=$(curl --silent --show-error --max-time 5 -D "$TMPDIR/h1" -o "$TMPDIR/b1" -w '%{http_code}' \
        "http://127.0.0.1:$PX_PORT/echo" 2>"$TMPDIR/c1.err") || {
    echo "  [FAIL] a request to a proxy with a dead upstream got no answer (curl exit $?):"
    cat "$TMPDIR/c1.err"; exit 1
}
[ "$RESP" = "502" ] || { echo "  [FAIL] expected 502, got $RESP"; exit 1; }
grep -qi '^X-Aether-Proxy-Error: upstream_transport' "$TMPDIR/h1" || {
    echo "  [FAIL] no X-Aether-Proxy-Error: upstream_transport:"; cat "$TMPDIR/h1"; exit 1; }

# Two on one connection: both answered.
OUT=$(curl --silent --show-error --max-time 5 -o /dev/null -o /dev/null \
        -w '%{http_code} ' "http://127.0.0.1:$PX_PORT/echo" "http://127.0.0.1:$PX_PORT/echo" 2>"$TMPDIR/c2.err") || {
    echo "  [FAIL] two requests on one connection (curl exit $?):"; cat "$TMPDIR/c2.err"; exit 1; }
[ "$OUT" = "502 502 " ] || { echo "  [FAIL] two requests: expected '502 502 ', got '$OUT'"; exit 1; }

# The proxy is still serving.
kill -0 "$PX_PID" 2>/dev/null || { echo "  [FAIL] the proxy died"; exit 1; }
echo "  [PASS] http_proxy_dead_upstream"
