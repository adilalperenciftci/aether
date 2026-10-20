#!/bin/sh
# #3017: a call that never returns (`exit(n)`, `os.exit(n)`) leaves, by the
# one rule every "does this leave?" check uses (stmt_can_complete): an
# `or { }` handler or a value `match` arm ending in one needs no value and
# runs it as a statement; an `if` expression's branch made of it, or of any
# call returning nothing, is refused before C; W1002 names what the
# unreachable code follows. Each program runs on the default C path and the
# strict C11 one, and must print what it says and exit with the code it
# picks. Pruned from the generic .ae runner (the programs exit non-zero on
# purpose, and two must not compile).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then echo "  [SKIP] never_returns: $AE not built"; exit 0; fi
export AETHER_HOME="$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
CC_BIN="${CC:-cc}"
command -v "$CC_BIN" >/dev/null 2>&1 || CC_BIN=gcc
fail=0

# <program> <want stdout> <want exit code> <label> [AE_CC]
expect_run() {
    name="$1"; want_out="$2"; want_rc="$3"; label="$4"
    exe="$tmp/${name}_$label"
    if ! (cd "$SCRIPT_DIR" && AE_CC="$5" "$AE" build "$name.ae" -o "$exe" >"$tmp/build.log" 2>&1); then
        echo "  [FAIL] never_returns: $name.ae did not build ($label):"
        grep -m6 -iE "error" "$tmp/build.log" | sed 's/^/        /'
        fail=1; return
    fi
    "$exe" >"$tmp/out.txt" 2>/dev/null; rc=$?
    out="$(tr -d '\r' < "$tmp/out.txt")"
    if [ "$out" != "$want_out" ] || [ "$rc" -ne "$want_rc" ]; then
        echo "  [FAIL] never_returns: $name ($label) printed / exited wrong"
        printf 'got (exit %s):\n%s\nwant (exit %s):\n%s\n' "$rc" "$out" "$want_rc" "$want_out" | sed 's/^/        /'
        fail=1
    fi
}

# <program> <pattern the diagnostic must match>
expect_refused() {
    name="$1"; want="$2"
    if "$AETHERC" "$SCRIPT_DIR/$name.ae" "$tmp/$name.c" >"$tmp/$name.log" 2>&1; then
        echo "  [FAIL] never_returns: $name.ae compiled (it must be refused before C)"
        fail=1; return
    fi
    if ! grep -qE "$want" "$tmp/$name.log"; then
        echo "  [FAIL] never_returns: $name.ae refused, but not for the stated reason ($want):"
        sed 's/^/        /' "$tmp/$name.log" | head -6
        fail=1
    fi
}

for path in default nogcc; do
    cc=""
    [ "$path" = nogcc ] && cc="$CC_BIN -DAETHER_GCC_COMPAT=0"
    expect_run or_exit "a=2
b failed: odd" 7 "$path" "$cc"
    expect_run or_os_exit "quarter(8)=2 quarter(3)=-1" 3 "$path" "$cc"
    expect_run arm_exit "pick(0)=10
leaving from one" 6 "$path" "$cc"
done

expect_refused reject_if_exit "'exit' never returns, so this branch of the .if. expression gives no value"
expect_refused reject_if_void "'note' returns no value, so this branch of the .if. expression gives none"

# W1002 names the statement the unreachable code follows.
"$AETHERC" "$SCRIPT_DIR/unreachable.ae" "$tmp/unreachable.c" >"$tmp/unreachable.log" 2>&1
for want in "unreachable code after continue" "unreachable code after break" "unreachable code after exit()"; do
    if ! grep -qF "$want" "$tmp/unreachable.log"; then
        echo "  [FAIL] never_returns: no W1002 '$want' for unreachable.ae:"
        sed 's/^/        /' "$tmp/unreachable.log" | head -8
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] never_returns: exit leaves an or handler and a match arm on both C paths; an if branch with no value is refused; W1002 names break, continue and exit()"
fi
exit "$fail"
