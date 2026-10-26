#!/bin/sh
# std.http.middleware.use_real_ip: the client behind trusted proxies
# (#3212). server.ae trusts 127.0.0.1, ::1, 10.0.0.0/8 and 192.168.0.0/16.
#
# Verifies:
#   1. `X-Forwarded-For: 1.2.3.4, 10.0.0.1, 192.168.1.1` from the trusted
#      peer gives X-Real-IP=1.2.3.4: read from the right, the first
#      entry that is not a trusted proxy.
#   2. A request without X-Forwarded-For gets the peer as X-Real-IP.
#   3. Whitespace around an entry is stripped.
#   4. An X-Real-IP the client sent is replaced by the client the
#      middleware resolved, never trusted, and never doubled (#3169).
#   5. Entries a client writes left of the first untrusted one change
#      nothing.
#
# Skips cleanly when curl is missing.

# Skip on Windows — the HTTP server / proxy / middleware code path
# under test is platform-independent userland C; the Linux and
# macOS CI matrix entries already exercise every behaviour this
# test asserts. Each curl invocation under MSYS2 bash pays Cygwin
# fork-emulation + Defender + slower-than-POSIX localhost overhead
# (~10-100x POSIX's per-spawn cost), so running these on Windows
# adds minutes to the pipeline without adding coverage. Windows-
# specific runtime concerns (file I/O, process spawning, path
# handling) are covered by fs_*, std_ipc_*, run_lib_path, and
# ae_help tests respectively.
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        echo "  [SKIP-WIN] http_real_ip — HTTP server/proxy/middleware code is platform-independent; covered by POSIX matrix"
        exit 0
        ;;
esac

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$ROOT/tests/lib/wait_port.sh"
. "$ROOT/tests/lib/server_jobs.sh"
AE="$ROOT/build/ae"

if ! command -v curl >/dev/null 2>&1; then
    echo "  [SKIP] curl not on PATH"; exit 0
fi

TMPDIR="$(mktemp -d)"
SRV_PID=""
cleanup() {
    stop_server "$SRV_PID"
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

AETHER_HOME="$ROOT" "$AE" run "$SCRIPT_DIR/server.ae" >"$TMPDIR/srv.log" 2>&1 &
SRV_PID=$!

deadline=$(($(date +%s) + 15))
while [ "$(date +%s)" -lt "$deadline" ]; do
    if grep -q READY "$TMPDIR/srv.log" 2>/dev/null; then break; fi
    if ! kill -0 "$SRV_PID" 2>/dev/null; then
        echo "  [FAIL] server died:"; head -20 "$TMPDIR/srv.log"; exit 1
    fi
    sleep 0.1
done
PORT=$(read_ready_port "$TMPDIR/srv.log") || exit 1
wait_port "$PORT" || exit 1

URL="http://127.0.0.1:$PORT/whoami"

# Test 1: multi-hop X-Forwarded-For: the first untrusted entry from the
# right.
RESP1=$(curl --silent --show-error --max-time 5 \
              -H 'X-Forwarded-For: 1.2.3.4, 10.0.0.1, 192.168.1.1' \
              "$URL" 2>"$TMPDIR/c1.err") || {
    echo "  [FAIL] curl 1 failed:"; cat "$TMPDIR/c1.err"; exit 1
}
[ "$RESP1" = "ip=1.2.3.4" ] || {
    echo "  [FAIL] expected ip=1.2.3.4, got '$RESP1'"; exit 1
}

# Test 2: no X-Forwarded-For. The peer is the client, and X-Real-IP
# names it.
RESP2=$(curl --silent --show-error --max-time 5 \
              "$URL" 2>"$TMPDIR/c2.err") || {
    echo "  [FAIL] curl 2 failed:"; cat "$TMPDIR/c2.err"; exit 1
}
[ "$RESP2" = "ip=127.0.0.1" ] || {
    echo "  [FAIL] expected ip=127.0.0.1 (the peer), got '$RESP2'"; exit 1
}

# Test 3: whitespace around an entry is stripped.
RESP3=$(curl --silent --show-error --max-time 5 \
              -H 'X-Forwarded-For:   192.0.2.1   , 10.0.0.5' \
              "$URL" 2>"$TMPDIR/c3.err") || {
    echo "  [FAIL] curl 3 failed:"; cat "$TMPDIR/c3.err"; exit 1
}
[ "$RESP3" = "ip=192.0.2.1" ] || {
    echo "  [FAIL] expected ip=192.0.2.1 (whitespace stripped), got '$RESP3'"; exit 1
}

# Test 4 — single-IP X-Forwarded-For (most common direct-LB case).
RESP4=$(curl --silent --show-error --max-time 5 \
              -H 'X-Forwarded-For: 203.0.113.42' \
              "$URL" 2>"$TMPDIR/c4.err") || {
    echo "  [FAIL] curl 4 failed:"; cat "$TMPDIR/c4.err"; exit 1
}
[ "$RESP4" = "ip=203.0.113.42" ] || {
    echo "  [FAIL] expected ip=203.0.113.42, got '$RESP4'"; exit 1
}

# Test 5: the client supplies its own X-Real-IP beside X-Forwarded-For.
# It is replaced by the client the middleware resolved, 1.2.3.4, and
# not doubled. The middleware used to keep it, which let any client
# name itself (#3169: a header the client sends is no client identity).
RESP5=$(curl --silent --show-error --max-time 5 \
              -H 'X-Real-IP: already-set' \
              -H 'X-Forwarded-For: 1.2.3.4' \
              "$URL" 2>"$TMPDIR/c5.err") || {
    echo "  [FAIL] curl 5 failed:"; cat "$TMPDIR/c5.err"; exit 1
}
[ "$RESP5" = "ip=1.2.3.4" ] || {
    echo "  [FAIL] expected ip=1.2.3.4 (the client's X-Real-IP replaced), got '$RESP5'"; exit 1
}

# Test 6: entries a client writes left of the first untrusted one,
# which a proxy that appends keeps, change nothing (#3212).
RESP6=$(curl --silent --show-error --max-time 5 \
              -H 'X-Forwarded-For: 6.6.6.6, 1.2.3.4, 10.0.0.1' \
              "$URL" 2>"$TMPDIR/c6.err") || {
    echo "  [FAIL] curl 6 failed:"; cat "$TMPDIR/c6.err"; exit 1
}
[ "$RESP6" = "ip=1.2.3.4" ] || {
    echo "  [FAIL] expected ip=1.2.3.4 (a forged entry on the left ignored), got '$RESP6'"; exit 1
}

echo "  [PASS] real_ip middleware (the client behind trusted proxies)"
