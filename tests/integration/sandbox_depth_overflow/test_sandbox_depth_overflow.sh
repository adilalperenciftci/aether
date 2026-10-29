#!/bin/sh
# A grant pushed past the fixed stack capacity must refuse checks instead of
# letting the block run under only its less restrictive outer grants.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ]; then
    echo "  [SKIP] sandbox_depth_overflow: build/ae not built"
    exit 0
fi

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
if ! "$AE" build "$SCRIPT_DIR/prog.ae" -o "$TMP/prog" >"$TMP/build.log" 2>&1; then
    echo "  [FAIL] sandbox_depth_overflow: probe did not build"
    sed 's/^/          /' "$TMP/build.log" | tail -20
    exit 1
fi

set +e
out="$(AE_SANDBOX_DEPTH_SECRET=visible "$TMP/prog" 2>&1)"
rc=$?
set -e
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^overflow-visible=0$' &&
        printf '%s' "$out" | grep -q '^after-visible=1$'; then
    echo "  [PASS] sandbox stack overflow refuses the inner check"
    echo "PASS: sandbox_depth_overflow"
    exit 0
fi

echo "  [FAIL] sandbox stack overflow dropped the inner policy"
printf '%s\n' "$out" | sed 's/^/          /' | head -10
echo "FAIL: sandbox_depth_overflow (rc=$rc)"
exit 1
