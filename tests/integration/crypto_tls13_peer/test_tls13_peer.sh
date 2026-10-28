#!/bin/sh
# The pure TLS client against a scripted server (peer.ae) that sends what a
# broken or hostile server would: each case is a PEER_CASE, what the client
# must answer (OK, or an error containing the text), and what the peer must
# see from it (FINISHED, or the alert it must send, by number).
#
#   #3315  extensions in ServerHello and EncryptedExtensions (RFC 8446 4.2):
#          unsupported_extension (110) for what the client never offered,
#          illegal_parameter (47) for an offered one out of place or twice,
#          decode_error (50) for a block that does not parse.
#
# No network beyond loopback, no openssl: the peer's certificate is built in.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$ROOT/tests/lib/server_jobs.sh"
AE="$ROOT/build/ae"
NAME=crypto_tls13_peer

[ -x "$AE" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }

TMP="$(mktemp -d)"
PIDS=""
cleanup() {
    for p in $PIDS; do stop_server "$p"; done
    rm -rf "$TMP" || :
    return 0
}
trap cleanup EXIT
fail() { echo "  [FAIL] $NAME: $1"; exit 1; }

for p in peer client; do
    "$AE" build "$SCRIPT_DIR/$p.ae" -o "$TMP/$p" >"$TMP/b_$p.log" 2>&1 \
        || { sed -n '1,12p' "$TMP/b_$p.log"; fail "$p did not build"; }
done

fails=0
# run_case <name> <PEER_CASE> <client expects> <peer expects>
run_case() {
    rm -f "$TMP/port" "$TMP/peer.out"
    PEER_CASE="$2" PEER_CERT_OUT="$TMP/peer.pem" PEER_PORT_OUT="$TMP/port" "$TMP/peer" >"$TMP/peer.out" 2>&1 &
    ppid=$!
    PIDS="$PIDS $ppid"
    i=0
    while [ "$i" -lt 100 ] && [ ! -s "$TMP/port" ]; do sleep 0.1; i=$((i + 1)); done
    [ -s "$TMP/port" ] || { cat "$TMP/peer.out"; fail "$1: the peer never listened"; }
    got=$(PEER_PORT="$(cat "$TMP/port")" CAFILE="$TMP/peer.pem" "$TMP/client" 2>&1 | grep -v 'warning' || :)
    n=0
    while server_alive "$ppid" && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    stop_server "$ppid"
    seen=$(cat "$TMP/peer.out")
    ok=1
    case "$got" in *"$3"*) ;; *) ok=0 ;; esac
    case "$seen" in *"$4"*) ;; *) ok=0 ;; esac
    if [ "$ok" = 1 ]; then
        echo "    ok: $1"
    else
        echo "    FAIL: $1: client said [$got], peer saw [$seen]; want [$3] and [$4]"
        fails=$((fails + 1))
    fi
}

run_case "a clean handshake" "" "OK" "FINISHED"

# #3315: EncryptedExtensions.
run_case "EE: an unknown extension" "ee_ext=fafa0000" "ERR" "ALERT 110"
run_case "EE: extended_master_secret (TLS 1.2)" "ee_ext=00170000" "ERR" "ALERT 110"
run_case "EE: renegotiation_info (TLS 1.2)" "ee_ext=ff01000100" "ERR" "ALERT 110"
run_case "EE: ec_point_formats (TLS 1.2)" "ee_ext=000b00020100" "ERR" "ALERT 110"
run_case "EE: early_data, not offered" "ee_ext=002a0000" "ERR" "ALERT 110"
run_case "EE: key_share, offered but out of place" "ee_ext=00330000" "ERR" "ALERT 47"
run_case "EE: supported_versions, out of place" "ee_ext=002b00020304" "ERR" "ALERT 47"
run_case "EE: the same extension twice" "ee_ext=000a00040002001d000a00040002001d" "ERR" "ALERT 47"
run_case "EE: ALPN naming h2, never offered" "ee_ext=001000050003026832" "ERR" "ALERT 47"
run_case "EE: ALPN naming http/1.1" "ee_ext=0010000b000908687474702f312e31" "OK" "FINISHED"
run_case "EE: an empty server_name ack" "ee_ext=00000000" "OK" "FINISHED"
run_case "EE: a server_name ack with a body" "ee_ext=0000000100" "ERR" "ALERT 50"
run_case "EE: supported_groups" "ee_ext=000a00040002001d" "OK" "FINISHED"
run_case "EE: no extensions block at all" "ee_body=-" "ERR" "ALERT 50"

# #3315: ServerHello.
run_case "SH: an unknown extension" "sh_ext=fafa0000" "ERR" "ALERT 110"
run_case "SH: server_name, offered but out of place" "sh_ext=00000000" "ERR" "ALERT 47"
run_case "SH: pre_shared_key in a full handshake" "sh_ext=002900020000" "ERR" "ALERT 110"
run_case "SH: supported_versions twice" "sh_ext=002b00020304" "ERR" "ALERT 47"

[ "$fails" = 0 ] || fail "$fails case(s)"
echo "  [PASS] $NAME"
