#!/bin/sh
# Regression for #1092: std.tcp exposes a readiness primitive (poll/poll2)
# and a recv-timeout no longer masquerades as a connection close. Together
# these let a poll-driven client service a server-speaks-first stream that
# a half-duplex relay would stall on.

# Runs on Windows too: std.tcp's poll is a Winsock path of its own
# (WSAPoll and a recv timeout that must not read as a close), which no
# POSIX lane exercises. The skip that stood here ("covered by POSIX
# matrix") hid exactly that half.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
. "$ROOT/tests/lib/server_jobs.sh"

TMPDIR="$(mktemp -d)"
AETHER_CACHE_DIR="$TMPDIR/cache"
export AETHER_CACHE_DIR
SRV_PID=""
cleanup() {
    # `ae run` compiles, then runs the built binary as its child, which holds
    # the listen socket. stop_server's SIGTERM is relayed to that child on
    # POSIX, and on Windows ae keeps the child in a job object that goes
    # with ae, so the child does not outlive the test (and leak the port).
    stop_server "$SRV_PID"
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

AETHER_HOME="$ROOT" "$AE" run "$SCRIPT_DIR/server.ae" >"$TMPDIR/srv.log" 2>&1 &
SRV_PID=$!

# No READY-grep or port probe: the server's stdout is block-buffered to
# this pipe while it blocks in accept(), and a probe connect would steal
# the single accept slot. Instead the CLIENT self-synchronizes — it
# retries connect() until the listen socket is up (see client.ae). We
# only guard against the server dying before the client can connect.
sleep 0.5
if ! kill -0 "$SRV_PID" 2>/dev/null; then
    echo "  [FAIL] server died during startup:"
    head -30 "$TMPDIR/srv.log"
    exit 1
fi

AETHER_HOME="$ROOT" "$AE" run "$SCRIPT_DIR/client.ae" >"$TMPDIR/client.out" 2>&1 || {
    echo "  [FAIL] client exited non-zero:"
    cat "$TMPDIR/client.out"
    echo "--- server log ---"
    head -30 "$TMPDIR/srv.log"
    exit 1
}

cat "$TMPDIR/client.out"
