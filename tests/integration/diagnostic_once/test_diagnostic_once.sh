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

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] diagnostic_once: a wrong lane and an unknown bitstruct field are each reported once, in every place"
fi
exit $fail
