#!/bin/sh
# Multi-accept (#3194): http.server_set_multi_accept turns it on, and in
# actor dispatch mode the server opens its SO_REUSEPORT listeners on one
# port, after a server_bind on port 0 and without one. See multi_accept.ae.
# Where the kernel does not spread connections across the listeners
# (Windows, macOS, OpenBSD, NetBSD) the program checks that the setter
# says so.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

fail() { echo "  [FAIL] http_server_multi_accept: $1"; exit 1; }

if [ ! -x "$AE" ]; then
    echo "  [SKIP] http_server_multi_accept: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$ROOT/tests/lib/sweep_timeout.sh"
sweep_timeout_bound TO "$ROOT" 60

AETHER_HOME="$ROOT" "$AE" build "$SCRIPT_DIR/multi_accept.ae" -o "$TMP/multi_accept" \
    --extra "$SCRIPT_DIR/actor_shim.c" >"$TMP/build.log" 2>&1 \
    || { cat "$TMP/build.log"; fail "the program did not build"; }
OUT="$($TO "$TMP/multi_accept" 2>&1)"
RC=$?
[ "$RC" -eq 0 ] || { echo "$OUT"; fail "multi-accept did not start or serve (exit $RC, 124 is the time limit)"; }
[ "$OUT" = "MULTI-ACCEPT-OK" ] || { echo "$OUT"; fail "the program printed something of its own"; }

echo "  [PASS] http_server_multi_accept: listeners on one port where the kernel spreads connections, refused elsewhere"
