#!/bin/sh
# An if expression whose branches give values of types neither of which
# takes the other (#2983), an int and a string or two structs no sum holds
# both of, passed the checker and failed in C's `?:` ("pointer/integer type
# mismatch in conditional expression"). The language reference says both
# branches give a value of one type. It is refused, naming both types.
# Numbers keep joining to their common type (#2854), a branch another one's
# type takes (an int beside a `long?`, a variant beside its sum, `none`
# beside anything an optional slot wraps) still builds, and two variants of
# one sum are the sum (#2996).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT" && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] if_expression_branch_types: aetherc not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0

cat > "$tmp/bad.ae" <<'AE'
struct Circle {
    r: float
}

struct Rect {
    w: float
}

struct Tri {
    a: float
}

type Shape = Circle | Rect

main() {
    c = 1
    a = if c == 1 { 1 } else { "s" }
    u = if c == 1 { Circle { r: 1.0 } } else { Tri { a: 1.0 } }
    println("${a}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/bad.ae" 2>&1)"
for want in \
    "bad.ae:17:[0-9]* .*the branches of this if expression give values of types int and string" \
    "bad.ae:18:[0-9]* .*the branches of this if expression give values of types Circle and Tri"; do
    if ! printf '%s\n' "$out" | awk '/^error/ { m = $0; next } /-->/ && m != "" { print $2 " " m; m = "" }' | grep -q "$want"; then
        echo "  [FAIL] if_expression_branch_types: no diagnostic matching: $want"
        fail=1
    fi
done
[ $fail -ne 0 ] && printf '%s\n' "$out" | grep -E "^error|-->" | head -8 | sed 's/^/        |/'

cat > "$tmp/good.ae" <<'AE'
struct Circle {
    r: float
}

struct Rect {
    w: float
}

type Shape = Circle | Rect

main() {
    c = 1
    long big = 6000000000
    b = if c == 2 { 1 } else { big }
    f = if c == 2 { 1 } else { 2.5 }
    let o: int? = if c == 1 { 3 } else { none }
    let k: long? = 4
    q = if c == 1 { k } else { 5 }
    let sh: Shape = Rect { w: 2.0 }
    t = if c == 1 { sh } else { Circle { r: 2.0 } }
    let w: float = match t {
        Circle -> t.r
        Rect -> t.w
    }
    v = if c == 2 { Circle { r: 3.0 } } else { sh }
    let x: float = match v {
        Circle -> v.r
        Rect -> v.w + 1.0
    }
    z = if c == 2 { 5 } else { k }
    y = if c == 2 { Circle { r: 1.0 } } else { Rect { w: 7.0 } }
    let yw: float = match y {
        Circle -> y.r
        Rect -> y.w
    }
    println("${b} ${f} ${o ?? 0} ${q ?? 0} ${w} ${x} ${z ?? 0} ${yw}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AE" run "$tmp/good.ae" 2>&1)"
if [ "$out" != "6000000000 2.5 3 4 2 3 4 7" ]; then
    echo "  [FAIL] if_expression_branch_types: the branches of one type should build and run"
    printf '%s\n' "$out" | head -10 | sed 's/^/        |/'
    fail=1
fi

[ $fail -eq 0 ] && echo "  [PASS] if_expression_branch_types: branches of no common type are refused; numbers, optionals, sums and two variants of one sum build"
exit $fail
