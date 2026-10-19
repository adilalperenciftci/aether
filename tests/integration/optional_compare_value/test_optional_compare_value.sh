#!/bin/sh
# An optional compared with a bare value (`lo == 3` with `lo: int?`, `b.v
# == 3` with a field `v: int?`) passed the type checker and failed in C:
# "invalid operands to binary == (have 'ae_opt_int' and 'int')". `== none`
# and a comparison of two optionals were emitted as optionals; a bare value
# was neither wrapped nor refused. It is now compared as it would be wrapped
# into the optional, as a binding wraps it: equal when the optional is
# present with an equal value, a `string?` by its contents. Both operands are
# evaluated, in source order. An operand the optional cannot hold (`int?`
# against a `string` or a `string?`) is refused at the comparison.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT" && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] optional_compare_value: aetherc not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0

cat > "$tmp/good.ae" <<'AE'
struct Box {
    v: int?
}

next(n: int) -> int {
    println("next ${n}")
    return n + 1
}

maybe(n: int) -> int? {
    println("maybe ${n}")
    if n > 0 {
        return n
    }
    return none
}

name(n: int) -> string? {
    if n > 0 {
        return "n${n}"
    }
    return none
}

main() {
    let lo: int? = 3
    let no: int? = none
    b = Box { v: 3 }
    println("${lo == 3} ${lo != 3} ${3 == lo} ${lo == 4} ${no == 3} ${no != 3}")
    println("${b.v == 3} ${b.v != 3}")
    long big = 3
    println("${lo == big}")
    println("${maybe(1) == next(0)}")
    println("${next(0) == maybe(1)}")
    let s: string? = "abc"
    t = "ab"
    println("${s == "abc"} ${s == t} ${s != "abc"} ${"abc" == s}")
    println("${name(2) == "n2"} ${name(0) == "n2"} ${s == "${t}c"}")
}
AE
want="true false true false false true
true false
true
maybe 1
next 0
true
next 0
maybe 1
true
true false false true
true false true"
out="$(AETHER_HOME="$ROOT" "$AE" run "$tmp/good.ae" 2>&1)"
if [ "$out" != "$want" ]; then
    echo "  [FAIL] optional_compare_value: an optional compared with a bare value"
    printf '%s\n' "$out" | head -12 | sed 's/^/        |/'
    fail=1
fi

cat > "$tmp/bad.ae" <<'AE'
main() {
    let a: int? = 3
    let s: string? = "x"
    println("${a == s}")
    println("${a != "x"}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" "$tmp/bad.ae" "$tmp/bad.c" 2>&1)"
for want in \
    "bad.ae:4:[0-9]* .*'==' compares the optional 'int?' with 'string?', which it cannot hold" \
    "bad.ae:5:[0-9]* .*'!=' compares the optional 'int?' with 'string', which it cannot hold"; do
    # Each diagnostic as one line: its message, then its `--> file:line:col`.
    if ! printf '%s\n' "$out" | awk '/^error\[/ { m = $0; next } /-->/ && m != "" { print $2 " " m; m = "" }' | grep -q "$want"; then
        echo "  [FAIL] optional_compare_value: no diagnostic matching: $want"
        printf '%s\n' "$out" | head -12 | sed 's/^/        |/'
        fail=1
    fi
done

[ $fail -eq 0 ] && echo "  [PASS] optional_compare_value: an optional compares with a bare value as with it wrapped; one it cannot hold is refused"
exit $fail
