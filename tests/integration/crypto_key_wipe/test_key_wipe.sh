#!/bin/sh
# The pure TLS server's key loading leaves no copy of a private key in freed
# memory (#3382): probe.ae (with probe_shim.c, aether.toml) loads and frees
# four test keys and looks for their secrets in the blocks the C allocator
# hands out next. Its control, a freed buffer that was not wiped, must be
# found first; where it is not, the probe proves nothing and the test is a
# skip. Windows (the UCRT heap) and glibc hand freed blocks back as they
# were; a sanitizer or Valgrind skips.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
NAME=crypto_key_wipe
[ -x "$AE" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$SCRIPT_DIR" || exit 1
"$AE" build probe.ae -o "$TMP/probe" >"$TMP/build.log" 2>&1 \
    || { sed -n '1,12p' "$TMP/build.log"; echo "  [FAIL] $NAME: probe.ae did not build"; exit 1; }
out=$("$TMP/probe" 2>&1)
rc=$?
case "$out" in
    SKIP*) echo "  [SKIP] $NAME: ${out#SKIP: }"; exit 0 ;;
esac
echo "$out" | sed 's/^/    /'
if [ "$rc" -ne 0 ]; then
    echo "  [FAIL] $NAME"
    exit 1
fi
echo "  [PASS] $NAME"
