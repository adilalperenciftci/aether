#!/bin/sh
# #3426: a program that imports the pure TLS stack (std.cryptography.
# tls13_server, and through it tls13_client) and not std.http links nothing
# of the HTTP server or the HTTP client.
#
# The modules told std.http why a load or a handshake failed through a
# function of std/net/aether_http_server.c or std/net/aether_http.c, and the
# client read the Windows trust store through two more of aether_http.c, so
# every program that imported them pulled both objects out of libaether.a,
# and with the server the HTTP/2 object: on macOS, where Homebrew's nghttp2
# makes it the real one, such a program did not link
# ("_nghttp2_session_callbacks_new", referenced from aether_h2.o). The reason
# now goes through the callback registry (aether_callback_set_reason), which
# both sides already link, and the trust store has a file of its own
# (std/net/aether_tls_trust.c).
#
# The pure server of crypto_tls13_peer is built. Its symbols must hold
# tcp_socket_from_fd_owned (what the server module calls on every platform,
# so the check reads a binary that has symbols) and neither
# http_server_create (the HTTP server's) nor http_get_raw (the client's).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
NAME=tls13_server_link_surface

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }
command -v nm >/dev/null 2>&1 || { echo "  [SKIP] $NAME: no nm to read the binary's symbols"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT
fail() { echo "  [FAIL] $NAME: $1"; exit 1; }

"$AE" build "$ROOT/tests/integration/crypto_tls13_peer/server.ae" -o "$TMP/server" >"$TMP/build.log" 2>&1 \
    || { sed -n '1,12p' "$TMP/build.log"; fail "the pure server did not build"; }
# .exe first: MSYS2's test -f finds "server" when only server.exe exists.
bin="$TMP/server.exe"
[ -f "$bin" ] || bin="$TMP/server"
nm "$bin" > "$TMP/syms.txt" 2>&1 || { head -3 "$TMP/syms.txt"; fail "nm could not read $bin"; }

grep -q "tcp_socket_from_fd_owned" "$TMP/syms.txt" \
    || fail "the binary has no tcp_socket_from_fd_owned: nothing to judge (stripped, or the module changed)"
bad=0
for s in http_server_create http_get_raw; do
    if grep -q "$s" "$TMP/syms.txt"; then
        echo "    $s is in a program without std.http"
        bad=1
    fi
done
[ "$bad" = 0 ] || fail "a program without std.http links the HTTP layer"
echo "  [PASS] $NAME: the pure TLS stack links nothing of the HTTP server or client"
