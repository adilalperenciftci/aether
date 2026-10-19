#!/bin/sh
# The branches of a value give it one type, or are refused (#2983, #2996,
# #3003, #3004).
#
# An if expression's branches and a value match's arms join by one rule
# (branch_join_type): numbers, an optional beside its value, a sum beside its
# variant and two variants of one sum, fixed-size arrays of one element type
# and length, tuples position by position. Branches of no one type are an
# error naming both types: arrays of another length or element type, tuples
# of another length or element type, a struct beside a string. Two variants
# that two sums share are no one sum by themselves; the local's annotation
# or the result type says which, and is then accepted.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] branch_join_reject: aetherc not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0

check_errors() {  # file, then the "file:line:col message" patterns it must report
    f="$1"
    shift
    out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/$f" 2>&1)"
    for want in "$@"; do
        if ! printf '%s\n' "$out" | awk '/^error/ { m = $0; next } /-->/ && m != "" { print $2 " " m; m = "" }' | grep -q "$want"; then
            echo "  [FAIL] branch_join_reject: no diagnostic matching: $want"
            printf '%s\n' "$out" | grep -E "^error|-->" | head -8 | sed 's/^/        |/'
            fail=1
        fi
    done
}

cat > "$tmp/bad.ae" <<'AE'
struct Circle {
    r: int
}

struct Square {
    side: int
}

type Shape = Circle | Square
type Corner = Circle | Square

main() {
    k = 1
    a = [1, 2, 3]
    b = [1, 2]
    f = [1.5, 2.5, 3.5]
    v = match k { 0 -> a _ -> b }
    w = if k == 0 { a } else { f }
    t = match k { 0 -> (1, "a") _ -> (2, 3) }
    u = if k == 0 { (1, "a") } else { (2, "b", 3) }
    s = match k { 0 -> Circle { r: 1 } _ -> Square { side: 2 } }
    p = if k == 0 { Circle { r: 1 } } else { "x" }
    println("done")
}
AE
check_errors bad.ae \
    "bad.ae:17:[0-9]* .*the arms of this match give values of types int\[3\] and int\[2\]" \
    "bad.ae:18:[0-9]* .*the branches of this if expression give values of types int\[3\] and float\[3\]" \
    "bad.ae:19:[0-9]* .*the arms of this match give values of types (int, string) and (int, int)" \
    "bad.ae:20:[0-9]* .*the branches of this if expression give values of types (int, string) and (int, string, int)" \
    "bad.ae:21:[0-9]* .*the arms of this match give values of types Circle and Square" \
    "bad.ae:22:[0-9]* .*the branches of this if expression give values of types Circle and string"

cat > "$tmp/good.ae" <<'AE'
struct Circle {
    r: int
}

struct Square {
    side: int
}

type Shape = Circle | Square
type Corner = Circle | Square

pick(k: int) -> Corner {
    return match k { 0 -> Circle { r: 1 } _ -> Square { side: 2 } }
}

main() {
    k = 1
    let s: Shape = match k { 0 -> Circle { r: 1 } _ -> Square { side: 2 } }
    let t: Corner = if k == 0 { Circle { r: 1 } } else { Square { side: 2 } }
    c = pick(k)
    n = match k { 0 -> 1 _ -> 2000000000000 }
    println("done")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/good.ae" 2>&1)"
if printf '%s\n' "$out" | grep -q "^error"; then
    echo "  [FAIL] branch_join_reject: branches that join, or that the annotation types, were refused"
    printf '%s\n' "$out" | grep -E "^error|-->" | head -8 | sed 's/^/        |/'
    fail=1
fi

if [ $fail -eq 0 ]; then
    echo "  [PASS] branch_join_reject: branches give one type or are refused, and an annotation picks the sum"
fi
exit $fail
