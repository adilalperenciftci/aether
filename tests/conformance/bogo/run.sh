#!/bin/sh
# BoGo, BoringSSL's TLS test suite (ssl/test/runner), against the pure-Aether
# TLS 1.3 stack through shim.ae (#1298): std.cryptography.tls13_client, and
# tls13_server for the tests where the shim is the server.
#
#   sh tests/conformance/bogo/run.sh [runner flags, e.g. -test 'Basic-*']
#
# BoringSSL is fetched at a pinned commit (git checks every object against
# the commit's hash) into $CONFORMANCE_CACHE (default
# $HOME/.cache/aether-conformance); it is never committed. No CI job runs
# BoGo: it is run by hand (make conformance-bogo), and needs Go (go.mod says
# which; 1.27 at this commit) and git. ci-crypto-ct caches the same
# directory for x509-limbo, not for this.
# config.json disables each test that fails, with the reason; a test that
# fails and is not disabled fails the run. Tests that need a flag the shim
# does not implement exit 89 and count as "unimplemented"
# (-allow-unimplemented); the shim's header lists the flags it handles.

set -e

BORINGSSL_COMMIT=e651545da6e26e1f4420723a3b69a78ed1b9c51d

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
CACHE="${CONFORMANCE_CACHE:-$HOME/.cache/aether-conformance}"
SRC="$CACHE/boringssl-$BORINGSSL_COMMIT"

[ -x "$AE" ] || { echo "  [FAIL] bogo: build/ae is not built"; exit 1; }
command -v go >/dev/null 2>&1 || { echo "  [FAIL] bogo: no go to build the runner"; exit 1; }

if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || :)" != "$BORINGSSL_COMMIT" ]; then
    rm -rf "$SRC"
    mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin https://github.com/google/boringssl
    git -C "$SRC" sparse-checkout set ssl/test/runner util >/dev/null 2>&1 || :
    git -C "$SRC" fetch -q --depth 1 --filter=blob:none origin "$BORINGSSL_COMMIT" \
        || { echo "  [FAIL] bogo: could not fetch BoringSSL $BORINGSSL_COMMIT"; exit 1; }
    git -C "$SRC" checkout -q FETCH_HEAD
    [ "$(git -C "$SRC" rev-parse HEAD)" = "$BORINGSSL_COMMIT" ] \
        || { echo "  [FAIL] bogo: BoringSSL is not at $BORINGSSL_COMMIT"; exit 1; }
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$AE" build "$SCRIPT_DIR/shim.ae" -o "$TMP/shim" >"$TMP/build.log" 2>&1 \
    || { sed -n '1,20p' "$TMP/build.log"; echo "  [FAIL] bogo: shim.ae did not build"; exit 1; }
SHIM="$TMP/shim"
[ -x "$SHIM.exe" ] && SHIM="$SHIM.exe"
(cd "$SRC/ssl/test/runner" && go test -c -o "$TMP/runner" .) >"$TMP/runner.log" 2>&1 \
    || { sed -n '1,20p' "$TMP/runner.log"; echo "  [FAIL] bogo: the runner did not build"; exit 1; }
RUNNER="$TMP/runner"
[ -x "$RUNNER.exe" ] && RUNNER="$RUNNER.exe"
CONFIG="$SCRIPT_DIR/config.json"
if command -v cygpath >/dev/null 2>&1; then
    # The runner is a native Windows program there: give it Windows paths.
    SHIM=$(cygpath -m "$SHIM"); CONFIG=$(cygpath -m "$CONFIG")
fi

# The runner reads its certificates and keys relative to its directory.
start=$(date +%s)
rc=0
(cd "$SRC/ssl/test/runner" && "$RUNNER" -shim-path "$SHIM" -shim-config "$CONFIG" \
    -allow-unimplemented -loose-errors -pipe -num-workers "${BOGO_WORKERS:-4}" "$@") >"$TMP/out.txt" 2>&1 || rc=1
passed=$(grep -c "^PASSED (" "$TMP/out.txt" || :)
failed=$(grep -c "^FAILED (" "$TMP/out.txt" || :)
unimpl=$(grep -c "^UNIMPLEMENTED (" "$TMP/out.txt" || :)
summary="$passed passed, $failed failed, $unimpl unimplemented; config.json disables the rest"
if [ "$rc" = 0 ] && [ "$failed" = 0 ]; then
    echo "  [PASS] bogo ($(( $(date +%s) - start )) s): $summary"
    exit 0
fi
[ -n "$BOGO_OUT" ] && cp "$TMP/out.txt" "$BOGO_OUT"
grep -A14 "^FAILED (" "$TMP/out.txt" | head -300
tail -5 "$TMP/out.txt"
echo "  [FAIL] bogo: $summary"
exit 1
