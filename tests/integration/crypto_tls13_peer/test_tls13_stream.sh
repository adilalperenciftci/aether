#!/bin/sh
# A pure TLS connection's memory over a long stream (#3379): the pure client
# sends STREAM_MB MiB (200 by default) in 16 KiB records to the pure server,
# which then sends as much back. The record reader on each side keeps only
# what it has not consumed, so each reader's heap grows by less than
# GROWTH_MAX bytes (4 MiB) between its first 8 MiB and its last byte; a
# reader that kept everything it received grew by the whole stream.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$ROOT/tests/lib/server_jobs.sh"
AE="$ROOT/build/ae"
NAME=crypto_tls13_stream
MB="${STREAM_MB:-200}"
GROWTH_MAX=4194304

[ -x "$AE" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }

TMP="$(mktemp -d)"
SPID=""
cleanup() {
    [ -n "$SPID" ] && stop_server "$SPID"
    rm -rf "$TMP" || :
    return 0
}
trap cleanup EXIT
fail() { echo "  [FAIL] $NAME: $1"; exit 1; }

"$AE" build "$SCRIPT_DIR/stream.ae" -o "$TMP/stream" >"$TMP/b.log" 2>&1 \
    || { sed -n '1,12p' "$TMP/b.log"; fail "stream.ae did not build"; }

ROLE=server STREAM_MB="$MB" PORT_OUT="$TMP/port" CERT_OUT="$TMP/cert.pem" "$TMP/stream" >"$TMP/server.out" 2>&1 &
SPID=$!
i=0
while [ "$i" -lt 100 ] && [ ! -s "$TMP/port" ]; do sleep 0.1; i=$((i + 1)); done
[ -s "$TMP/port" ] || { cat "$TMP/server.out"; fail "the server never listened"; }
ROLE=client STREAM_MB="$MB" PORT="$(cat "$TMP/port")" CERT="$TMP/cert.pem" "$TMP/stream" >"$TMP/client.out" 2>&1
n=0
while server_alive "$SPID" && [ "$n" -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
stop_server "$SPID"
SPID=""

bytes=$((MB * 1048576))
for who in server client; do
    line=$(cat "$TMP/server.out" "$TMP/client.out" | grep "^$who read" | head -1)
    case "$line" in
        "$who read $bytes grew "*) ;;
        *) echo "    server: $(cat "$TMP/server.out")"; echo "    client: $(cat "$TMP/client.out")"; fail "the $who did not read the whole stream" ;;
    esac
    grew=${line##* grew }
    [ "$grew" -lt "$GROWTH_MAX" ] || fail "the $who's heap grew by $grew bytes over a $MB MiB stream"
    echo "    ok: the $who read $MB MiB, its heap grew by $grew bytes"
done
echo "  [PASS] $NAME"
