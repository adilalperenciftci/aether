#!/bin/sh
# A wrong lane name and an unknown bitstruct field are each reported once
# (#3042). Inference and the check walk both reported them, and inference
# runs on a node from several places, so one typo printed its E0200 two or
# three times; an `if` or `while` on it added "condition must be boolean".
# Each site below must carry its message exactly once, and nothing else.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] diagnostic_once: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

cat > "$TMP/once.ae" <<'AE'
import std.lanes

bitstruct Hdr : uint16_t {
    qr: bool 15
}

struct S { f: float }

use_f(x: float) -> float { return x }

lane_q(v: f32x4) -> float {
    return v.q
}

main() {
    v = lanes.f32x4(1.0, 2.0, 3.0, 4.0)
    d = lanes.f64x2(1.0, 2.0)
    w = lanes.splat8(1.0)
    h = 0 as Hdr
    a = v.q
    println(d.z)
    println("${h.nope}")
    b = use_f(w.q) + 1.0
    if h.nope { println("x") }
    while h.gone { println("y") }
    s = S { f: v.r }
    g = || { return v.s }
    c = h.none
}
AE

out=$(cd "$TMP" && "$AE" check once.ae 2>&1)
# Each error with the position after it, one a line.
pairs=$(printf '%s\n' "$out" | awk '/^error/ { msg = $0; next } /-->/ && msg != "" { print $2 " " msg; msg = "" }')

# expect <position> <text>: exactly one error at that position, containing text.
expect() {
    n=$(printf '%s\n' "$pairs" | grep -c "^once.ae:$1 ")
    m=$(printf '%s\n' "$pairs" | grep "^once.ae:$1 " | grep -cF "$2")
    if [ "$n" -ne 1 ] || [ "$m" -ne 1 ]; then
        echo "  [FAIL] diagnostic_once: $n error(s) at $1, $m with \"$2\""
        fail=1
    fi
}
expect 12:13 "'q' is not a lane of f32x4"
expect 20:10 "'q' is not a lane of f32x4"
expect 21:14 "'z' is not a lane of f64x2"
expect 22:17 "'nope' is not a field of bitstruct 'Hdr'"
expect 23:16 "'q' is not a lane of f32x8"
expect 24:9 "'nope' is not a field of bitstruct 'Hdr'"
expect 25:12 "'gone' is not a field of bitstruct 'Hdr'"
expect 26:17 "'r' is not a lane of f32x4"
expect 27:22 "'s' is not a lane of f32x4"
expect 28:10 "'none' is not a field of bitstruct 'Hdr'"

total=$(printf '%s\n' "$out" | grep -c "^error")
if [ "$total" -ne 10 ]; then
    echo "  [FAIL] diagnostic_once: $total errors, want 10:"
    printf '%s\n' "$out" | grep -A1 "^error" | sed 's/^/        /'
    fail=1
fi

# #3042 review: a condition that reported its own error is not also "not
# boolean", and the branches are still checked: an undefined name in the
# body of an `if` and a `while` on a typo is reported too (the check
# returned at the condition, and the body was never read).
cat > "$TMP/bodies.ae" <<'AE'
import std.lanes

bitstruct Hdr : uint16_t {
    qr: bool 15
}

main() {
    v = lanes.f32x4(1.0, 2.0, 3.0, 4.0)
    h = 0 as Hdr
    if v.q > 0.0 {
        println("${undefined_one}")
    }
    while h.gone {
        println("${undefined_two}")
    }
}
AE
out=$(cd "$TMP" && "$AE" check bodies.ae 2>&1)
for want in "'q' is not a lane of f32x4" "'gone' is not a field of bitstruct 'Hdr'" \
            "Undefined variable 'undefined_one'" "Undefined variable 'undefined_two'"; do
    n=$(printf '%s\n' "$out" | grep "^error" | grep -cF "$want")
    if [ "$n" -ne 1 ]; then
        echo "  [FAIL] diagnostic_once: bodies.ae reports \"$want\" $n time(s), want 1"
        fail=1
    fi
done
total=$(printf '%s\n' "$out" | grep -c "^error")
if [ "$total" -ne 4 ]; then
    echo "  [FAIL] diagnostic_once: bodies.ae has $total errors, want 4:"
    printf '%s\n' "$out" | grep -A1 "^error" | sed 's/^/        /'
    fail=1
fi

# The same for a `for` loop's condition, which still added "For loop
# condition must be boolean" after the field's error; and that message, for
# a condition that is not boolean, is at the condition (it was at 0:0).
cat > "$TMP/forloop.ae" <<'AE'
bitstruct Hdr : uint16_t {
    qr: bool 15
}

main() {
    h = 0 as Hdr
    for (i = 0; h.nope; i = i + 1) {
        println("${undefined_three}")
    }
    for (j = 0; j + 1; j = j + 1) {
        println("${j}")
    }
}
AE
out=$(cd "$TMP" && "$AE" check forloop.ae 2>&1)
pairs=$(printf '%s\n' "$out" | awk '/^error/ { msg = $0; next } /-->/ && msg != "" { print $2 " " msg; msg = "" }')
for want in "forloop.ae:7:18 error[E0200]: 'nope' is not a field of bitstruct 'Hdr'" \
            "Undefined variable 'undefined_three'" \
            "forloop.ae:10:19 error[E0200]: For loop condition must be boolean"; do
    n=$(printf '%s\n' "$pairs" | grep -cF "$want")
    if [ "$n" -ne 1 ]; then
        echo "  [FAIL] diagnostic_once: forloop.ae reports \"$want\" $n time(s), want 1"
        fail=1
    fi
done
total=$(printf '%s\n' "$out" | grep -c "^error")
if [ "$total" -ne 3 ]; then
    echo "  [FAIL] diagnostic_once: forloop.ae has $total errors, want 3:"
    printf '%s\n' "$out" | grep -A1 "^error" | sed 's/^/        /'
    fail=1
fi

# A bare optional as a condition is `o != none` written wrong: one error,
# whose hint says so, and the branch checked as that would narrow it (a
# loop's body is not narrowed by `while o != none` either, so it reads `o`
# only in ways that check unnarrowed). A condition that is no optional and
# no bool still leaves its body checked.
cat > "$TMP/optional.ae" <<'AE'
struct Shape { x: int }

in_if(o: Shape?) -> int {
    if o {
        return o.x
    }
    return 0
}

in_while(o: Shape?) -> int {
    n = 0
    while o {
        n = n + 1
        o = none
    }
    return n
}

not_optional(n: int) {
    if n + 1 {
        println("${undefined_four}")
    }
}

main() {
    not_optional(in_if(none) + in_while(none))
}
AE
out=$(cd "$TMP" && "$AE" check optional.ae 2>&1)
pairs=$(printf '%s\n' "$out" | awk '/^error/ { msg = $0; next } /-->/ && msg != "" { print $2 " " msg; msg = "" }')
for want in "optional.ae:4:8 error[E0200]: If condition must be boolean" \
            "optional.ae:12:11 error[E0200]: Loop condition must be boolean" \
            "optional.ae:20:10 error[E0200]: If condition must be boolean" \
            "Undefined variable 'undefined_four'"; do
    n=$(printf '%s\n' "$pairs" | grep -cF "$want")
    if [ "$n" -ne 1 ]; then
        echo "  [FAIL] diagnostic_once: optional.ae reports \"$want\" $n time(s), want 1"
        fail=1
    fi
done
for want in "test it with \`o != none\`"; do
    n=$(printf '%s\n' "$out" | grep -cF "$want")
    if [ "$n" -ne 2 ]; then
        echo "  [FAIL] diagnostic_once: optional.ae gives the hint \"$want\" $n time(s), want 2"
        fail=1
    fi
done
total=$(printf '%s\n' "$out" | grep -c "^error")
if [ "$total" -ne 4 ]; then
    echo "  [FAIL] diagnostic_once: optional.ae has $total errors, want 4:"
    printf '%s\n' "$out" | grep -A1 "^error" | sed 's/^/        /'
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] diagnostic_once: a wrong lane and an unknown bitstruct field are each reported once, in every place, a condition's error leaves its body checked, and a bare optional condition is one error"
fi
exit $fail
