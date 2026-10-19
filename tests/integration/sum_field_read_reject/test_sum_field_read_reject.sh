#!/bin/sh
# A variant's field read on a sum value no `match` narrows (#2986), `s.r`
# with `s: Shape` outside a match, or `h.sh.r` in an arm of `match h.sh`,
# passed the checker and failed in C ("'Shape' has no member named 'r'").
# A `match` narrows a plain variable it matches on, as the language
# reference says; anything else is refused now, naming the sum and the
# field, and the help says to bind the value to a local and match on that.
# The narrowed forms build and run.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT" && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] sum_field_read_reject: aetherc not built"
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

type Shape = Circle | Rect

struct Holder {
    sh: Shape
}

main() {
    let s: Shape = Circle { r: 1.5 }
    h = Holder { sh: s }
    x = s.r
    let y: float = match h.sh {
        Circle -> h.sh.r
        Rect -> 0.0
    }
    println("${x} ${y}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/bad.ae" 2>&1)"
for want in \
    "bad.ae:18:[0-9]* .*the sum type 'Shape' has no field 'r'" \
    "bad.ae:20:[0-9]* .*the sum type 'Shape' has no field 'r'"; do
    if ! printf '%s\n' "$out" | awk '/^error/ { m = $0; next } /-->/ && m != "" { print $2 " " m; m = "" }' | grep -q "$want"; then
        echo "  [FAIL] sum_field_read_reject: no diagnostic matching: $want"
        fail=1
    fi
done
if ! printf '%s' "$out" | grep -q 'bind the value to a local and match on that'; then
    echo "  [FAIL] sum_field_read_reject: the help does not say to match on a local"
    fail=1
fi
[ $fail -ne 0 ] && printf '%s\n' "$out" | grep -E "^error|-->|help" | head -10 | sed 's/^/        |/'

cat > "$tmp/good.ae" <<'AE'
struct Circle {
    r: float
}

struct Rect {
    w: float
}

type Shape = Circle | Rect

struct Holder {
    sh: Shape
}

radius(s: Shape) -> float {
    let a: float = match s {
        Circle -> s.r
        Rect -> s.w
    }
    return a
}

main() {
    h = Holder { sh: Circle { r: 2.5 } }
    v = h.sh
    let y: float = match v {
        Circle -> v.r
        Rect -> 0.0
    }
    println("${radius(Rect { w: 4.0 })} ${y}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AE" run "$tmp/good.ae" 2>&1)"
if [ "$out" != "4 2.5" ]; then
    echo "  [FAIL] sum_field_read_reject: the narrowed reads should build and run"
    printf '%s\n' "$out" | head -8 | sed 's/^/        |/'
    fail=1
fi

[ $fail -eq 0 ] && echo "  [PASS] sum_field_read_reject: a variant field read on a sum no match narrows is refused; narrowed reads build"
exit $fail
