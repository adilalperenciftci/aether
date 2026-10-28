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
#   #3317  the record layer (RFC 8446 5): limits, types, change_cipher_spec,
#          empty records; client and server.
#   #3321  handshake messages split across records, client and server.
#   #3316  CertificateEntry extensions (RFC 8446 4.4.2): the same alerts,
#          and decode_error for a status_request that is not one OCSP
#          response.
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

for p in peer client server rawclient; do
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
    cr=0
    case "$2" in *post=*) cr=1 ;; esac
    got=$(CLIENT_READ="$cr" PEER_PORT="$(cat "$TMP/port")" CAFILE="$TMP/peer.pem" "$TMP/client" 2>&1 | grep -v 'warning' || :)
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


# #3316: CertificateEntry extensions (RFC 8446 4.4.2).
run_case "Certificate: an unknown entry extension" "cert_ext=fafa0000" "ERR" "ALERT 110"
run_case "Certificate: an SCT, never offered" "cert_ext=00120000" "ERR" "ALERT 110"
run_case "Certificate: server_name, offered but out of place" "cert_ext=00000000" "ERR" "ALERT 47"
run_case "Certificate: status_request with no response" "cert_ext=00050000" "ERR" "ALERT 50"
run_case "Certificate: status_request twice" "cert_ext=0005000501000001000005000501000001ff" "ERR" "ALERT 47"
run_case "Certificate: one stapled response" "cert_ext=0005000501000001ff" "OK" "FINISHED"


# #3317: the record layer (RFC 8446 5).
run_case "flight: the one compatibility change_cipher_spec" "ccs=1" "OK" "FINISHED"
run_case "flight: two change_cipher_spec records" "ccs=2" "ERR" "ALERT 10"
run_case "flight: a change_cipher_spec of value 2" "ccs=bad" "ERR" "ALERT 10"
run_case "flight: an empty protected handshake record" "empty_hs=1" "ERR" "ALERT 10"
run_case "flight: EncryptedExtensions in the clear" "plain_ee=1" "ERR" "ALERT 10"
run_case "flight: bytes after the Finished in its record" "fin_trailing=1" "ERR" "ALERT 10"
run_case "after: a record of 2^14 + 1 bytes" "post=oversize" "RECVERR" "POST ALERT 22"
run_case "after: 8193 bytes padded past 2^14 + 1" "post=padded" "RECVERR" "POST ALERT 22"
run_case "after: a protected record over 2^14 + 256" "post=bigcipher" "RECVERR" "POST ALERT 22"
run_case "after: 40 empty records" "post=empty40" "RECVERR" "POST ALERT 10"
run_case "after: 10 empty records, then data" "post=empty10" "RECV 2" "POST"
run_case "after: a change_cipher_spec" "post=ccs" "RECVERR" "POST ALERT 10"
run_case "after: a record of unknown type" "post=badtype" "RECVERR" "POST ALERT 10"
run_case "after: a protected record of unknown inner type" "post=innertype" "RECVERR" "POST ALERT 10"
run_case "after: a record that does not authenticate" "post=badmac" "RECVERR" "POST ALERT 20"
run_case "after: an empty handshake record" "post=emptyhs" "RECVERR" "POST ALERT 10"

# run_server_case <name> <RAW hex the client sends> <answer expected>
run_server_case() {
    rm -f "$TMP/port" "$TMP/server.out"
    PEER_PORT_OUT="$TMP/port" "$TMP/server" >"$TMP/server.out" 2>&1 &
    spid=$!
    PIDS="$PIDS $spid"
    i=0
    while [ "$i" -lt 100 ] && [ ! -s "$TMP/port" ]; do sleep 0.1; i=$((i + 1)); done
    [ -s "$TMP/port" ] || { cat "$TMP/server.out"; fail "$1: the server never listened"; }
    got=$(RAW="$2" PEER_PORT="$(cat "$TMP/port")" "$TMP/rawclient" 2>&1 | grep -v 'warning' || :)
    n=0
    while server_alive "$spid" && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    stop_server "$spid"
    case "$got" in
        *"$3"*) echo "    ok: $1" ;;
        *) echo "    FAIL: $1: the server answered [$got], server said [$(cat "$TMP/server.out")]; want [$3]"; fails=$((fails + 1)) ;;
    esac
}

# #3317, the pure server's record layer: refused from the header alone.
run_server_case "server: a record of unknown type first" "180303000100" "ALERT 10"
run_server_case "server: a plaintext record over 2^14" "1603034001" "ALERT 22"
run_server_case "server: a change_cipher_spec before the ClientHello" "140303000101" "ALERT 10"

# #3321: a handshake message split across records (RFC 8446 5.1).
run_case "SH: split into 8-byte records" "split_sh=8" "OK" "FINISHED"
run_case "SH: split into 1-byte records" "split_sh=1" "OK" "FINISHED"
run_case "SH: more handshake bytes after it in its record" "pack_sh=1" "ERR" "ALERT 10"
run_server_case "server: a ClientHello split over two records" "split_ch" "SERVERHELLO"

[ "$fails" = 0 ] || fail "$fails case(s)"
echo "  [PASS] $NAME"
