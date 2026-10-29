#!/bin/sh
# Each thread installs and restores its own in-process sandbox checker. One
# thread leaving an enforce block must not disable another thread's policy.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "$(uname -s 2>/dev/null)" in
    Linux|FreeBSD|Darwin) ;;
    *)
        echo "  [SKIP] sandbox_checker_tls: POSIX thread harness"
        exit 0 ;;
esac
if [ ! -f "$ROOT/build/libaether.a" ]; then
    echo "  [SKIP] sandbox_checker_tls: build/libaether.a not built"
    exit 0
fi

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
if ! ${CC:-cc} -std=c11 -Wall -Wextra -Werror -DAETHER_HAS_SANDBOX \
        -I"$ROOT/runtime" -o "$TMP/harness" "$SCRIPT_DIR/harness.c" \
        "$ROOT/build/libaether.a" -lpthread -lm 2>"$TMP/cc.err"; then
    echo "  [FAIL] sandbox_checker_tls: harness did not compile"
    sed 's/^/          /' "$TMP/cc.err" | head -10
    exit 1
fi

out="$($TMP/harness 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q \
        '^PASS: sandbox checker state is thread-local$'; then
    echo "  [PASS] sandbox checker state is thread-local"
    echo "PASS: sandbox_checker_tls"
    exit 0
fi

echo "  [FAIL] sandbox checker state crossed threads"
printf '%s\n' "$out" | sed 's/^/          /' | head -10
echo "FAIL: sandbox_checker_tls"
exit 1
