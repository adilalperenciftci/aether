#!/bin/sh
# `ae fmt` keeps an `or` handler's parenthesis apart, a statement's leading
# `-` on its operand, and the space after a postfix `!` (#2818).
#
# `e = num(true) or (num(false) or { 1 })` came out as `or(num(false) ...`,
# which reads as a call of a function `or`: after a value, `or` is the
# error handler's keyword and what follows it an expression. A block's last
# line `-2` came out as `- 2`, which reads as the second half of a
# subtraction from the line above: the parser never continues an expression
# with an operator on a new line, so an operator that begins a line is a
# prefix one, as a line-leading `*` already was (`- calls` is `-calls`).
# And `small(3)! + num(true)!` came out as `small(3)! +num(true)!`: a `!`
# written tight after a value is its postfix unwrap and ends a value, so
# the `+` after it is infix. The formatted program is run, to show it means
# what the input did.
#
# The input and the expected output are here rather than as .ae files, so
# the fmt gate and the .ae sweep do not pick them up.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] fmt_prefix_after_value: ae not built"
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/in.ae" <<'EOF'
num(fail: bool) -> int! {
    if fail { return 0, "boom" }
    return 7
}

main() {
    calls = 0
    e = num(true) or (num(false) or { 1 })
    z = num(true) or {
        calls = calls + 10
        -2
    }
    w = num(true) or {
        calls = calls + 1
        - calls
    }
    s = num(false)! + num(false)!
    t = num(false)! -num(false)!
    n = -s
    println("${e} ${z} ${w} ${s} ${t} ${n}")
}
EOF

cat >"$TMPDIR/want.ae" <<'EOF'
num(fail: bool) -> int! {
    if fail { return 0, "boom" }
    return 7
}

main() {
    calls = 0
    e = num(true) or (num(false) or { 1 })
    z = num(true) or {
        calls = calls + 10
        -2
    }
    w = num(true) or {
        calls = calls + 1
        -calls
    }
    s = num(false)! + num(false)!
    t = num(false)! - num(false)!
    n = -s
    println("${e} ${z} ${w} ${s} ${t} ${n}")
}
EOF

cp "$TMPDIR/in.ae" "$TMPDIR/got.ae"
if ! "$AE" fmt "$TMPDIR/got.ae" >"$TMPDIR/fmt.log" 2>&1; then
    echo "  [FAIL] fmt_prefix_after_value: ae fmt failed"
    sed 's/^/          /' "$TMPDIR/fmt.log" | head -10
    exit 1
fi
if [ "$(cat "$TMPDIR/want.ae")" != "$(cat "$TMPDIR/got.ae")" ]; then
    echo "  [FAIL] fmt_prefix_after_value: output differs from the expected layout; got:"
    sed 's/^/          /' "$TMPDIR/got.ae" | head -30
    exit 1
fi

# The formatted program means what the input did.
out="$(AETHER_HOME="$ROOT" "$AE" run "$TMPDIR/got.ae" 2>&1 | tr -d '\r' | tail -1)"
if [ "$out" != "7 -2 -11 14 0 -14" ]; then
    echo "  [FAIL] fmt_prefix_after_value: the formatted program printed: $out"
    exit 1
fi

# Formatting the output again changes nothing.
cp "$TMPDIR/want.ae" "$TMPDIR/again.ae"
"$AE" fmt "$TMPDIR/again.ae" >/dev/null 2>&1
if [ "$(cat "$TMPDIR/want.ae")" != "$(cat "$TMPDIR/again.ae")" ]; then
    echo "  [FAIL] fmt_prefix_after_value: formatting the output again changed it"
    exit 1
fi

echo "  [PASS] fmt_prefix_after_value: or (, a line-leading -2 and a postfix ! keep their spelling"
exit 0
