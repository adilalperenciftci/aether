#!/bin/sh
# An allowed exec with an explicit environment must retain the preload layer
# and its grant source. Omitting or replacing control entries must not turn the
# child into an unrestricted process.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LIB="$ROOT/build/libaether_sandbox.so"

case "$(uname -s 2>/dev/null)" in
    Linux|FreeBSD) ;;
    *)
        echo "  [SKIP] sandbox_exec_env_inherit: preload is Linux and FreeBSD only"
        exit 0 ;;
esac
if [ ! -f "$LIB" ]; then
    echo "  [SKIP] sandbox_exec_env_inherit: preload library not built"
    exit 0
fi

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
if ! ${CC:-cc} -std=c11 -Wall -Wextra -Werror \
        "$SCRIPT_DIR/launcher.c" -o "$TMP/launcher"; then
    echo "  [FAIL] sandbox_exec_env_inherit: launcher did not compile"
    exit 1
fi

printf 'exec sentinel\n' > "$TMP/data.txt"
printf 'exec:/bin/cat\n' > "$TMP/deny-read.grants"
printf 'exec:/bin/cat\nfs_read:%s\n' "$TMP/data.txt" > "$TMP/allow-read.grants"
printf 'exec:/usr/bin/env\n' > "$TMP/env.grants"
fail=0

expect_denied() {
    mode="$1"
    if LD_PRELOAD="$LIB" AETHER_SANDBOX_GRANTS="$TMP/deny-read.grants" \
            AETHER_SANDBOX_LOG=none "$TMP/launcher" "$TMP/data.txt" "$mode" \
            >"$TMP/out" 2>"$TMP/err"; then
        echo "  [FAIL] explicit env ($mode) dropped containment: child exited zero"
        fail=1
    elif grep -qF 'exec sentinel' "$TMP/out"; then
        echo "  [FAIL] explicit env ($mode) dropped containment: child read the file"
        fail=1
    else
        echo "  [PASS] explicit env ($mode) retains containment"
    fi
}

expect_denied omit
expect_denied override

if LD_PRELOAD="$LIB" AETHER_SANDBOX_GRANTS="$TMP/allow-read.grants" \
        AETHER_SANDBOX_LOG=none "$TMP/launcher" "$TMP/data.txt" omit \
        >"$TMP/out" 2>"$TMP/err" && grep -qF 'exec sentinel' "$TMP/out"; then
    echo "  [PASS] inherited controls preserve an allowed exec"
else
    echo "  [FAIL] inherited controls broke an allowed exec"
    sed 's/^/        /' "$TMP/err" | head -8
    fail=1
fi

if LD_PRELOAD="$LIB" AETHER_SANDBOX_GRANTS="$TMP/env.grants" \
        AETHER_SANDBOX_LOG=none "$TMP/launcher" ignored env \
        >"$TMP/out" 2>"$TMP/err" &&
        grep -qxF 'ONLY=explicit' "$TMP/out" &&
        grep -qxF "LD_PRELOAD=$LIB" "$TMP/out" &&
        grep -qxF "AETHER_SANDBOX_GRANTS=$TMP/env.grants" "$TMP/out"; then
    echo "  [PASS] explicit entries and sandbox controls reach the child"
else
    echo "  [FAIL] merged child environment lost explicit or sandbox entries"
    sed 's/^/        /' "$TMP/out" | head -12
    fail=1
fi

echo ""
echo "sandbox_exec_env_inherit: $([ "$fail" -eq 0 ] && echo PASS || echo FAIL)"
[ "$fail" -eq 0 ]
