#!/bin/sh
# The pure TLS server checks each CertificateVerify signature against its
# certificate's key before sending it (#3376).
#
# A signature computed wrongly (a fault in the arithmetic, a bit flipped in
# memory) can disclose the private key: one faulty RSA-CRT signature
# factors the modulus, and two of one message under a deterministic nonce
# give the ECDSA or Ed25519 key. The server never sends one that does not
# verify; it ends the handshake with internal_error instead.
#
# The pure server of crypto_tls13_peer (tls13_server.accept, which takes
# the chain and key as given, with no pair check) and openssl s_client, for
# each scheme the server signs: ECDSA P-256, P-384 and P-521, Ed25519, and
# RSA as rsa_pss_rsae_sha256, _sha384 and _sha512.
#
#   1. The certificate with its own key: s_client completes and names the
#      scheme, so the check passes every good signature.
#   2. The certificate with another key of its type, standing in for a
#      signature gone wrong: the server refuses to send it and says so, and
#      s_client gets internal_error (80), not a signature it rejects (a
#      server that sent it made s_client fail with decrypt_error or a bad
#      signature).
#
# Skipped without openssl.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$ROOT/tests/lib/server_jobs.sh"
AE="$ROOT/build/ae"
NAME=crypto_tls13_signature_check

[ -x "$AE" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }
command -v openssl >/dev/null 2>&1 || { echo "  [SKIP] $NAME: no openssl"; exit 0; }
unset SSL_CERT_FILE SSL_CERT_DIR || :

TMP="$(mktemp -d)"
. "$ROOT/tests/lib/test_openssl_conf.sh"
test_openssl_conf "$TMP"
PIDS=""
cleanup() {
    for p in $PIDS; do stop_server "$p"; done
    rm -rf "$TMP" || :
    return 0
}
trap cleanup EXIT
fail() { echo "  [FAIL] $NAME: $1"; exit 1; }
ssl() { "$@" >"$TMP/ssl.log" 2>&1 || { sed -n '1,10p' "$TMP/ssl.log"; fail "openssl: $*"; }; }

"$AE" build "$ROOT/tests/integration/crypto_tls13_peer/server.ae" -o "$TMP/server" >"$TMP/b_server.log" 2>&1 \
    || { sed -n '1,12p' "$TMP/b_server.log"; fail "server did not build"; }

# A self-signed certificate for peer.example and a second key, of key
# type $1 (the genpkey arguments follow).
make_pair() {
    t="$1"
    shift
    ssl openssl genpkey "$@" -out "$TMP/$t.key"
    ssl openssl genpkey "$@" -out "$TMP/$t.other.key"
    MSYS2_ARG_CONV_EXCL='/CN=' ssl openssl req -x509 -new -key "$TMP/$t.key" -out "$TMP/$t.pem" -days 2 \
        -subj "/CN=peer.example" -addext "subjectAltName=DNS:peer.example"
}
make_pair p256 -algorithm EC -pkeyopt ec_paramgen_curve:P-256
make_pair p384 -algorithm EC -pkeyopt ec_paramgen_curve:P-384
make_pair p521 -algorithm EC -pkeyopt ec_paramgen_curve:P-521
make_pair ed25519 -algorithm ED25519
make_pair rsa -algorithm RSA -pkeyopt rsa_keygen_bits:2048

fails=0
# serve <cert> <key> <s_client -sigalgs>: one connection; the server's
# output lands in $TMP/server.out and s_client's in $TMP/c.log.
serve() {
    rm -f "$TMP/port" "$TMP/server.out"
    SERVER_CERT="$1" SERVER_KEY="$2" PEER_PORT_OUT="$TMP/port" "$TMP/server" >"$TMP/server.out" 2>&1 &
    spid=$!
    PIDS="$PIDS $spid"
    i=0
    while [ "$i" -lt 100 ] && [ ! -s "$TMP/port" ]; do sleep 0.1; i=$((i + 1)); done
    [ -s "$TMP/port" ] || { cat "$TMP/server.out"; fail "the pure server never listened"; }
    openssl s_client -connect "127.0.0.1:$(cat "$TMP/port")" -servername peer.example -sigalgs "$3" \
        </dev/null >"$TMP/c.log" 2>&1 || :
    n=0
    while server_alive "$spid" && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    stop_server "$spid"
}

# check <key type> <sigalg> <the name s_client gives the signature type>
check() {
    serve "$TMP/$1.pem" "$TMP/$1.key" "$2"
    if grep -q "Peer signature type: $3" "$TMP/c.log" && grep -q ACCEPTED "$TMP/server.out"; then
        echo "    ok: $2: its own key's signature is sent"
    else
        echo "    FAIL: $2, its own key: server [$(tr '\n' '|' <"$TMP/server.out")], s_client [$(grep -i 'signature type\|alert\|error' "$TMP/c.log" | tr '\n' '|')]"
        fails=$((fails + 1))
    fi
    serve "$TMP/$1.pem" "$TMP/$1.other.key" "$2"
    if grep -q "REFUSED: .*not sent" "$TMP/server.out" && grep -qi "alert internal error\|alert number 80" "$TMP/c.log"; then
        echo "    ok: $2: a signature that does not verify is not sent (internal_error)"
    else
        echo "    FAIL: $2, another key: server [$(tr '\n' '|' <"$TMP/server.out")], s_client [$(grep -i 'alert\|error' "$TMP/c.log" | tr '\n' '|')]"
        fails=$((fails + 1))
    fi
}

check p256 ecdsa_secp256r1_sha256 ecdsa_secp256r1_sha256
check p384 ecdsa_secp384r1_sha384 ecdsa_secp384r1_sha384
check p521 ecdsa_secp521r1_sha512 ecdsa_secp521r1_sha512
check ed25519 ed25519 ed25519
check rsa rsa_pss_rsae_sha256 rsa_pss_rsae_sha256
check rsa rsa_pss_rsae_sha384 rsa_pss_rsae_sha384
check rsa rsa_pss_rsae_sha512 rsa_pss_rsae_sha512

[ "$fails" = 0 ] || fail "$fails case(s)"
echo "  [PASS] $NAME"
