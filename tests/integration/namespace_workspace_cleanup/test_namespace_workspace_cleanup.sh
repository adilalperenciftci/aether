#!/bin/sh
# #2773: `ae build --namespace` works in <temp>/aether_ns_<pid> and left it
# behind after every build, built or failed: a machine that runs the sweep
# collected hundreds. ae gets a temp directory of the test's own (TMPDIR, and
# TEMP/TMP, which a native ae.exe reads on Windows), runs a namespace build
# that succeeds and one that fails, and the directory must hold no
# aether_ns_* afterwards.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SRC="$ROOT/tests/integration/namespace_basic"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "  [FAIL] namespace_workspace_cleanup: $1"; exit 1; }

mkdir -p "$TMP/temp" "$TMP/ok" "$TMP/empty"
cp "$SRC/manifest.ae" "$SRC/hello.ae" "$TMP/ok/"
cp "$SRC/manifest.ae" "$TMP/empty/"
if command -v cygpath >/dev/null 2>&1; then
    native_temp="$(cygpath -m "$TMP/temp")"
else
    native_temp="$TMP/temp"
fi

leftovers() { ls "$TMP/temp" 2>/dev/null | grep '^aether_ns_' ; }

( cd "$TMP/ok" && TMPDIR="$TMP/temp" TEMP="$native_temp" TMP="$native_temp" \
    AETHER_HOME="" "$ROOT/build/ae" build --namespace . ) >"$TMP/ok.log" 2>&1 \
    || { cat "$TMP/ok.log"; fail "the namespace build failed"; }
grep -q "Built namespace" "$TMP/ok.log" || { cat "$TMP/ok.log"; fail "no 'Built namespace' line"; }
left=$(leftovers)
[ -z "$left" ] || fail "a namespace build that succeeded left $left in the temp directory"

# A manifest with no scripts fails after the workspace is made.
( cd "$TMP/empty" && TMPDIR="$TMP/temp" TEMP="$native_temp" TMP="$native_temp" \
    AETHER_HOME="" "$ROOT/build/ae" build --namespace . ) >"$TMP/empty.log" 2>&1 \
    && { cat "$TMP/empty.log"; fail "a namespace with no scripts built"; }
grep -q "contains a manifest but no scripts" "$TMP/empty.log" \
    || { cat "$TMP/empty.log"; fail "the failed build did not say why"; }
left=$(leftovers)
[ -z "$left" ] || fail "a namespace build that failed left $left in the temp directory"

echo "  [PASS] namespace_workspace_cleanup: ae build --namespace removes its workspace, built or failed"
