#!/bin/sh
# A running TLS server re-loads its certificate while it accepts (#3371).
#
# server_set_tls on a running server swapped the OpenSSL context, and with
# #3362 the pure server's parsed credentials, without a lock: a connection
# accepted between reading the pointer and taking its own reference used
# freed memory. Two certificates for localhost, both signed by one root; an
# actor sets the server's TLS 200 times, in turn, while 100 fetches run, on
# each backend. Every fetch must succeed and nothing may crash (the
# sanitizer legs run this too).
#
# In a build without OpenSSL only the "aether" backend runs.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
NAME=https_tls_reload

[ -x "$AE" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }
command -v openssl >/dev/null 2>&1 || { echo "  [SKIP] $NAME: no openssl to make the certificates"; exit 0; }

unset SSL_CERT_FILE SSL_CERT_DIR AETHER_PURE_TLS || :

TMP="$(mktemp -d)"
. "$ROOT/tests/lib/test_openssl_conf.sh"
test_openssl_conf "$TMP"
trap 'rm -rf "$TMP" || :' EXIT
fail() { echo "  [FAIL] $NAME: $1"; exit 1; }
ssl() { "$@" >"$TMP/ssl.log" 2>&1 || { sed -n '1,10p' "$TMP/ssl.log"; fail "openssl: $*"; }; }

printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\nsubjectAltName=DNS:localhost\n' >"$TMP/leaf.ext"
for k in root a b; do
    ssl openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$TMP/$k.key"
done
MSYS2_ARG_CONV_EXCL='/CN=' ssl openssl req -x509 -new -key "$TMP/root.key" -out "$TMP/root.pem" \
    -days 2 -subj "/CN=Reload Test Root" -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
for k in a b; do
    MSYS2_ARG_CONV_EXCL='/CN=' ssl openssl req -new -key "$TMP/$k.key" -out "$TMP/$k.csr" -subj "/CN=localhost"
    ssl openssl x509 -req -in "$TMP/$k.csr" -CA "$TMP/root.pem" -CAkey "$TMP/root.key" -CAcreateserial \
        -days 2 -extfile "$TMP/leaf.ext" -out "$TMP/$k.pem"
done

"$AE" build "$SCRIPT_DIR/reload.ae" -o "$TMP/reload" >"$TMP/build.log" 2>&1 \
    || { sed -n '1,12p' "$TMP/build.log"; fail "reload.ae did not build"; }

BACKENDS="aether"
if BACKEND=openssl ROOT_CA="$TMP/root.pem" CERT_A=/nonexistent KEY_A=/nonexistent \
        "$TMP/reload" 2>&1 | grep -q "has no OpenSSL"; then :; else BACKENDS="aether openssl"; fi

for b in $BACKENDS; do
    out=$(BACKEND="$b" ROOT_CA="$TMP/root.pem" CERT_A="$TMP/a.pem" KEY_A="$TMP/a.key" \
          CERT_B="$TMP/b.pem" KEY_B="$TMP/b.key" "$TMP/reload" 2>&1) || :
    case "$out" in
        *"OK 100 of 100 after 200 loads"*) echo "    ok: $b backend: 100 fetches through 200 re-loads" ;;
        *) echo "$out" | tail -5 | sed 's/^/        /'; fail "$b backend: $out" ;;
    esac
done

echo "  [PASS] $NAME"
