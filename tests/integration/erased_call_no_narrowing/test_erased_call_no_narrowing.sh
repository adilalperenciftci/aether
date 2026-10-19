#!/bin/sh
# A call through an erased `fn` is dispatched to each closure of the program
# whose parameters take its arguments only coerced (#2847). A closure whose
# parameter took an argument only by narrowing it was a candidate too:
# `call(f, 0.5)` gained a branch calling `|a: int|` with 0.5, which no
# correct program reaches, and clang warned at it ("implicit conversion from
# 'double' to 'int' changes value from 0.5 to 0"), in the output of every
# program that built through it. A candidate now takes each argument by the
# assignment rules without narrowing, and a widening it needs (an int into a
# `long` or a `float` parameter) is an explicit cast. Built here with float
# conversions as errors, on the C compiler the suite uses.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] erased_call_no_narrowing: ae not built"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT

cat > "$tmp/main.ae" <<'AE'
apply_half(f: fn) -> float {
    return call(f, 0.5)
}

apply_long(f: fn) -> long {
    return call(f, 7)
}

main() {
    doubled = |a: int| -> a * 2.0
    halved = |x: float| -> x / 2.0
    widen = |n: long| -> n * 3
    shrink = |n: int| -> n + 1
    println("${call(doubled, 3)} ${apply_half(halved)} ${apply_long(widen)} ${call(shrink, 1)}")
}
AE

cc="${AE_CC:-${CC:-cc}}"
out="$(cd "$tmp" && AETHER_HOME="$ROOT" AE_CC="$cc -Werror=float-conversion" "$AE" run main.ae 2>&1)"
if [ "$out" != "6 0.25 21 2" ]; then
    echo "  [FAIL] erased_call_no_narrowing: built with float conversions as errors, printed:"
    printf '%s\n' "$out" | head -10 | sed 's/^/        |/'
    exit 1
fi
echo "  [PASS] erased_call_no_narrowing: an erased call reaches no closure by narrowing an argument"
