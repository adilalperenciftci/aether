#!/bin/sh
# An explicitly configured grant source is a containment request. If that
# source cannot be read, the preload layer must deny rather than silently run
# without a sandbox. With no source configured at all, preload remains inert.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LIB="$ROOT/build/libaether_sandbox.so"

case "$(uname -s 2>/dev/null)" in
    Linux|FreeBSD) ;;
    *)
        echo "  [SKIP] sandbox_source_fail_closed: preload is Linux and FreeBSD only"
        exit 0 ;;
esac
if [ ! -f "$LIB" ]; then
    echo "  [SKIP] sandbox_source_fail_closed: preload library not built"
    exit 0
fi

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
printf 'source sentinel\n' > "$TMP/data.txt"
printf '*:*\n' > "$TMP/allow-all.grants"
printf '*:*\n' > "$TMP/oversized.grants"
dd if=/dev/zero bs=8193 count=1 2>/dev/null | tr '\000' '#' >> "$TMP/oversized.grants"
missing_shm="/aether_sandbox_missing_$$"
missing_file="$TMP/missing.grants"
fail=0

expect_denied() {
    label="$1"
    shift
    if "$@" >"$TMP/out" 2>"$TMP/err"; then
        echo "  [FAIL] $label: cat exited zero"
        fail=1
    elif grep -qF 'source sentinel' "$TMP/out"; then
        echo "  [FAIL] $label: protected data was read"
        fail=1
    else
        echo "  [PASS] $label"
    fi
}

expect_allowed() {
    label="$1"
    shift
    if "$@" >"$TMP/out" 2>"$TMP/err" && grep -qF 'source sentinel' "$TMP/out"; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label: expected cat to read the file"
        sed 's/^/        /' "$TMP/err" | head -8
        fail=1
    fi
}

expect_denied "missing shared-memory source fails closed" \
    env -u AETHER_SANDBOX_GRANTS LD_PRELOAD="$LIB" \
        AETHER_SANDBOX_SHM="$missing_shm" AETHER_SANDBOX_LOG=none \
        /bin/cat "$TMP/data.txt"

expect_denied "missing grant-file source fails closed" \
    env -u AETHER_SANDBOX_SHM LD_PRELOAD="$LIB" \
        AETHER_SANDBOX_GRANTS="$missing_file" AETHER_SANDBOX_LOG=none \
        /bin/cat "$TMP/data.txt"

expect_denied "oversized grant-file source fails closed before parsing" \
    env -u AETHER_SANDBOX_SHM LD_PRELOAD="$LIB" \
        AETHER_SANDBOX_GRANTS="$TMP/oversized.grants" AETHER_SANDBOX_LOG=none \
        /bin/cat "$TMP/data.txt"

expect_allowed "valid grant file remains a fallback for missing shared memory" \
    env LD_PRELOAD="$LIB" AETHER_SANDBOX_SHM="$missing_shm" \
        AETHER_SANDBOX_GRANTS="$TMP/allow-all.grants" AETHER_SANDBOX_LOG=none \
        /bin/cat "$TMP/data.txt"

expect_allowed "preload without a configured source remains inert" \
    env -u AETHER_SANDBOX_SHM -u AETHER_SANDBOX_GRANTS LD_PRELOAD="$LIB" \
        AETHER_SANDBOX_LOG=none /bin/cat "$TMP/data.txt"

echo ""
echo "sandbox_source_fail_closed: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
[ "$fail" -eq 0 ]
