#!/bin/sh
# The pure TLS client's session resumption and 0-RTT, against a scripted
# server (resumepeer.ae) that knows the ticket the client holds and
# computes every secret itself, and against `openssl s_server -early_data`.
#
#   #3336  the application traffic secrets are over ClientHello..server
#          Finished, whether or not the server took the early data: the
#          EndOfEarlyData is the client Finished's only.
#   #3352  the EndOfEarlyData goes under the early traffic keys.
#   #3339  early data goes under the suite the ticket was issued under (a
#          ChaCha20 ticket included), a ticket naming none sends none, and
#          a server that takes it under another suite is refused.
#   #3355  conn_early_accepted says whether the early data was taken.
#   #3318  the server must take the one PSK identity offered, with a suite
#          of the ticket's hash (illegal_parameter).
#   #3353  a ServerHello without key_share (missing_extension) or naming a
#          group the ClientHello has no share for (illegal_parameter).
#   #3325  a HelloRetryRequest asking for secp256r1: the second ClientHello
#          carries its share, no early data, and a binder over the new
#          transcript.
#
# The scripted part needs nothing beyond loopback. The OpenSSL part is
# skipped without an openssl whose s_server has -early_data.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$ROOT/tests/lib/server_jobs.sh"
AE="$ROOT/build/ae"
NAME=crypto_tls13_resume

[ -x "$AE" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }
unset SSL_CERT_FILE SSL_CERT_DIR || :

TMP="$(mktemp -d)"
PIDS=""
cleanup() {
    for p in $PIDS; do stop_server "$p"; done
    rm -rf "$TMP" || :
    return 0
}
trap cleanup EXIT
fail() { echo "  [FAIL] $NAME: $1"; exit 1; }

for p in resumepeer resumeclient; do
    "$AE" build "$SCRIPT_DIR/$p.ae" -o "$TMP/$p" >"$TMP/b_$p.log" 2>&1 \
        || { sed -n '1,12p' "$TMP/b_$p.log"; fail "$p did not build"; }
done

fails=0
# run_case <name> <ticket suite> <PEER_CASE> <EARLY> <client expects> <peer expects>
# TSUITE overrides the suite the client's ticket names.
run_case() {
    rm -f "$TMP/port" "$TMP/peer.out"
    RESUME_SUITE="$2" PEER_CASE="$3" PEER_PORT_OUT="$TMP/port" "$TMP/resumepeer" >"$TMP/peer.out" 2>&1 &
    ppid=$!
    PIDS="$PIDS $ppid"
    i=0
    while [ "$i" -lt 100 ] && [ ! -s "$TMP/port" ]; do sleep 0.1; i=$((i + 1)); done
    [ -s "$TMP/port" ] || { cat "$TMP/peer.out"; fail "$1: the peer never listened"; }
    got=$(TICKET_SUITE="$TSUITE" RESUME_SUITE="$2" FIXED_TICKET=1 RESUME_READ=1 EARLY="$4" \
        RESUME_PORT="$(cat "$TMP/port")" RESUME_HOST=peer.example "$TMP/resumeclient" 2>&1 | tr '\n' '|')
    n=0
    while server_alive "$ppid" && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    stop_server "$ppid"
    seen=$(tr '\n' '|' <"$TMP/peer.out")
    ok=1
    case "$got" in *"$5"*) ;; *) ok=0 ;; esac
    case "$seen" in *"$6"*) ;; *) ok=0 ;; esac
    if [ "$ok" = 1 ]; then
        echo "    ok: $1"
    else
        echo "    FAIL: $1: client said [$got], peer saw [$seen]; want [$5] and [$6]"
        fails=$((fails + 1))
    fi
}

run_case "resume, no early data" 1301 "" "" "RESUMED early=0|SENT|RECV 2" "binder=ok early=0|FINISHED ok|DATA AFTER"
run_case "0-RTT taken, AES-128-GCM" 1301 "early=accept" HELLO "RESUMED early=1|SENT|RECV 2" "EARLY HELLO|EOED|FINISHED ok|DATA AFTER"
run_case "0-RTT taken, a ChaCha20-Poly1305 ticket" 1303 "early=accept" HELLO "RESUMED early=1|SENT|RECV 2" "EARLY HELLO|EOED|FINISHED ok|DATA AFTER"
run_case "0-RTT taken, AES-256-GCM-SHA384" 1302 "early=accept" HELLO "RESUMED early=1|SENT|RECV 2" "EARLY HELLO|EOED|FINISHED ok|DATA AFTER"
run_case "0-RTT refused" 1303 "" HELLO "RESUMED early=0|SENT|RECV 2" "EARLY HELLO|FINISHED ok|DATA AFTER"
TSUITE=0000 run_case "a ticket naming no suite sends no early data" 1301 "early=accept" HELLO "RESUMED early=0" "binder=ok early=0|FINISHED ok|DATA AFTER"
run_case "0-RTT taken under another suite than the ticket's" 1301 "suite=1303;early=accept" HELLO "RESUMEERR" "EARLY HELLO|ALERT 47"
run_case "a PSK identity never offered" 1301 "psk_id=1" "" "RESUMEERR" "ALERT 47"
run_case "a suite of another hash than the PSK's" 1301 "suite=1302" "" "RESUMEERR" "ALERT 47"
run_case "a ServerHello without key_share" 1301 "nokeyshare=1" "" "RESUMEERR" "ALERT 109"
run_case "a key_share for a group without a share" 1301 "group=0017" "" "RESUMEERR" "ALERT 47"
run_case "HRR for secp256r1" 1303 "hrr=group:0017" "" "RESUMED early=0|SENT|RECV 2" "CH2 binder=ok early=0|FINISHED ok|DATA AFTER"
run_case "HRR for secp256r1 after 0-RTT data" 1303 "hrr=group:0017;early=accept" HELLO "RESUMED early=0|SENT|RECV 2" "EARLY HELLO|CH2 binder=ok early=0|FINISHED ok|DATA AFTER"
run_case "HRR for x25519, which has a share" 1303 "hrr=group:001d" "" "RESUMEERR" "ALERT 47"

# Against OpenSSL: a full handshake for the ticket, then a resumption with
# 0-RTT data that s_server -www takes as a line it ignores, then the
# request under the new application keys and its answer under the
# server's, in each suite.
if command -v openssl >/dev/null 2>&1 && openssl s_server -help 2>&1 | grep -q -- '-early_data'; then
    . "$ROOT/tests/lib/test_openssl_conf.sh"
    test_openssl_conf "$TMP"
    MSYS2_ARG_CONV_EXCL='/CN=' openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "$TMP/k.pem" -out "$TMP/c.pem" -days 2 -nodes -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost" -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature" >"$TMP/ssl.log" 2>&1 \
        || { sed -n '1,12p' "$TMP/ssl.log"; fail "openssl could not make the certificate"; }
    for cs in TLS_AES_128_GCM_SHA256:4865 TLS_CHACHA20_POLY1305_SHA256:4867 TLS_AES_256_GCM_SHA384:4866; do
        suite=${cs%%:*}
        num=${cs##*:}
        SP=""
        for try in 1 2 3 4 5; do
            P=$(( 20000 + ($$ * 7 + try * 1009 + num) % 40000 ))
            # -4: IPv4 only, as https_client_pure_tls; -naccept 2: the full
            # handshake and the resumption, then it exits.
            openssl s_server -4 -www -accept "$P" -tls1_3 -early_data -num_tickets 1 -naccept 2 \
                -ciphersuites "$suite" -cert "$TMP/c.pem" -key "$TMP/k.pem" >"$TMP/s.log" 2>&1 </dev/null &
            spid=$!
            PIDS="$PIDS $spid"
            # Ready when it says ACCEPT: probing the port would use up one
            # of its two connections.
            w=0
            while [ "$w" -lt 100 ] && server_alive "$spid" && ! grep -q ACCEPT "$TMP/s.log" 2>/dev/null; do sleep 0.1; w=$((w + 1)); done
            if server_alive "$spid" && grep -q ACCEPT "$TMP/s.log" 2>/dev/null; then
                SP=$P
                break
            fi
            kill_server "$spid"
        done
        [ -n "$SP" ] || fail "could not start openssl s_server -early_data"
        got=$(RESUME_PORT="$SP" RESUME_HOST=localhost CAFILE="$TMP/c.pem" EARLY="X-Early: 1" AFTER=GET RESUME_READ=1 \
            "$TMP/resumeclient" 2>&1 | tr '\n' '|')
        n=0
        while server_alive "$spid" && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
        stop_server "$spid"
        case "$got" in
            *"TICKET suite=$num"*"RESUMED early=1|SENT|RECV "*"HTTP/1.0 200"*) echo "    ok: openssl s_server -early_data, $suite" ;;
            *) echo "    FAIL: openssl s_server -early_data, $suite: client said [$got]; server [$(tr '\n' '|' <"$TMP/s.log")]"; fails=$((fails + 1)) ;;
        esac
    done
else
    echo "    skip: openssl s_server -early_data (no openssl, or no -early_data)"
fi

[ "$fails" = 0 ] || fail "$fails case(s)"
echo "  [PASS] $NAME"
