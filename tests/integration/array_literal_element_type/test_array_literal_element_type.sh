#!/bin/sh
# An array literal's element type is the numeric join of ALL its elements,
# decided once they are typed (#2119).
#
# The early inference pass chose the element type from the first element
# before anything imported could be resolved, so `[0.18 * math.PI, ...]`
# with a module constant came out as an int array (the product's type was
# unknown then, and unknown lowers to int) and every element was truncated
# — a sweep of angles ran at 0 or 1 with no diagnostic. `[1, 2.5, 3]` had
# the same fate from its first element. Three places had to agree: the
# literal's type, the inferred declaration that adopts it, and an index
# expression that was stamped with the stale element type and reached
# printf as `%d` on a double slot.
#
# Also here, since they are the same slot: a float assigned to an int
# variable or int-array element whose type was INFERRED is the narrowing
# error #698 gives for a 64-bit value (it used to truncate silently and,
# for the variable, print garbage through `%g`), and a nested array
# literal is refused instead of emitting invalid C.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AE" ]; then
    echo "  [SKIP] array_literal_element_type: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0

mkdir -p "$tmp/lib/mathx"
cat > "$tmp/lib/mathx/module.ae" <<'AE'
exports(PI, half)

const PI = 3.14159265359

half(x: float) -> float { return x * 0.5 }
AE
cat > "$tmp/main.ae" <<'AE'
import mathx

main() {
    rolls = [ 0.18 * mathx.PI, 0.25 * mathx.PI, 0.32 * mathx.PI ]
    println("rolls ${rolls[0]} ${rolls[1]} ${rolls[2]}")
    mixed = [ 1, 2.5, 3 ]
    println("mixed ${mixed[0]} ${mixed[1]} ${mixed[2]}")
    calls = [ mathx.half(1.0), mathx.half(3.0) ]
    println("calls ${calls[0]} ${calls[1]}")
    ints = [ 1, 2, 3 ]
    println("ints ${ints[0]} ${ints[2]}")
    longs = [ 4000000000, 1 ]
    println("longs ${longs[0]} ${longs[1]}")
    k = mixed[1]
    s = mixed[1] + mixed[2]
    z = longs[0]
    println("derived ${k} ${s} ${z}")
    uint32 u = 4000000000
    us = [ u, 0 ]
    uint16 h = 65000
    hs = [ h, 1 ]
    println("narrow ${us[0]} ${hs[0]}")
    i = 0
    total = 0.0
    while i < 3 {
        total = total + rolls[i]
        i = i + 1
    }
    println("total ${total}")
}
AE
want='rolls 0.565487 0.785398 1.00531
mixed 1 2.5 3
calls 0.5 1.5
ints 1 3
longs 4000000000 1
derived 2.5 5.5 4000000000
narrow 4000000000 65000
total 2.35619'
got="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run main.ae 2>&1)"
if [ "$got" != "$want" ]; then
    echo "  [FAIL] array_literal_element_type: output differs"
    printf '%s\n' "$got" | head -8 | sed 's/^/        /'
    fail=1
fi

expect_error() {  # file, pattern, label
    out="$(AETHER_HOME="$ROOT" "$AETHERC" "$1" "$tmp/out.c" 2>&1)"
    if ! printf '%s' "$out" | grep -q "$2"; then
        echo "  [FAIL] array_literal_element_type: $3"
        printf '%s\n' "$out" | grep -E "^error|-->" | head -4 | sed 's/^/        /'
        fail=1
    fi
}

cat > "$tmp/narrow_var.ae" <<'AE'
main() {
    r = 0
    r = 2.5
    println("${r}")
}
AE
expect_error "$tmp/narrow_var.ae" "narrowing assignment to 'r': its type was inferred as int from its initializer, but a float is assigned" "a float into an inferred int variable was not refused"

cat > "$tmp/narrow_elem.ae" <<'AE'
main() {
    xs = [ 1, 2 ]
    xs[0] = 7.5
    println("${xs[0]}")
}
AE
expect_error "$tmp/narrow_elem.ae" "narrowing assignment to an element of 'xs'" "a float into an inferred int array element was not refused"

# An int array that came from a call, not a literal, is not "inferred from
# the array literal": it narrows like any other int slot, without the
# literal-shaped advice.
cat > "$tmp/from_call.ae" <<'AE'
mk() -> int[] {
    int[2] r = [ 1, 2 ]
    return r
}
main() {
    ys = mk()
    ys[0] = 7.5
    println("${ys[0]}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" "$tmp/from_call.ae" "$tmp/out.c" 2>&1)"
if printf '%s' "$out" | grep -q "from the array literal"; then
    echo "  [FAIL] array_literal_element_type: an int array bound from a call got the array-literal narrowing message"
    printf '%s\n' "$out" | grep -E "^error|-->" | head -4 | sed 's/^/        /'
    fail=1
fi

cat > "$tmp/nested.ae" <<'AE'
main() {
    grid = [ [ 1.0, 2.0 ], [ 3.0, 4.0 ] ]
    println("${grid[0][0]}")
}
AE
expect_error "$tmp/nested.ae" "an array literal cannot hold an array literal" "a nested array literal was not refused"

# #3067: every element goes into a slot of the element type. One the type
# cannot hold is refused at the element; it reached C as an initializer of
# the wrong type (`int` from `const char*`, a struct field from `void*`).
# `null` has no type of its own: it takes the others', and is refused only
# where that type takes no null.
cat > "$tmp/elem_string.ae" <<'AE'
main() {
    xs = [ 1, "x" ]
    println("${xs.len}")
}
AE
expect_error "$tmp/elem_string.ae" "array literal element 2 is 'string', which an array of 'int' cannot hold" "a string in an int array literal was not refused"

cat > "$tmp/elem_null_struct.ae" <<'AE'
struct P { x: int }
main() {
    p = P { x: 1 }
    ps = [ null, p ]
    println("${ps.len}")
}
AE
expect_error "$tmp/elem_null_struct.ae" "array literal element 1 is \`null\`, which an array of 'P' cannot hold" "null in a struct array literal was not refused"

cat > "$tmp/elem_closure_int.ae" <<'AE'
main() {
    k = 2
    f = | x: int | -> x + k
    fs = [ f, 3 ]
    println("${fs.len}")
}
AE
expect_error "$tmp/elem_closure_int.ae" "array literal element 2 is 'int', which an array of 'fn' cannot hold" "an int in a closure array literal was not refused"

cat > "$tmp/elem_null_string.ae" <<'AE'
main() {
    s = "hi"
    a = [ s, null ]
    b = [ null, s ]
    n = 0
    if a[1] == null { n = n + 1 }
    if b[0] == null { n = n + 1 }
    println("${a.len} ${b.len} ${n} ${b[1]}")
}
AE
got="$(AETHER_HOME="$ROOT" "$AE" run "$tmp/elem_null_string.ae" 2>&1 | tail -1)"
if [ "$got" != "2 2 2 hi" ]; then
    echo "  [FAIL] array_literal_element_type: null beside a string, either side, gave '$got'"
    fail=1
fi

# `none` has no type of its own either: `[none, x]` is an array of x's
# optional (it was an array of the optional of no type, and `??` on an
# element was refused), and a `none` beside an int is refused.
cat > "$tmp/elem_none_first.ae" <<'AE'
pick(k: int) -> int? {
    if k > 0 { return k }
    return none
}
main() {
    x = pick(3)
    a = [ x, none ]
    b = [ none, x ]
    println("${a[0] ?? -1} ${a[1] ?? -1} ${b[0] ?? -1} ${b[1] ?? -1}")
}
AE
got="$(AETHER_HOME="$ROOT" "$AE" run "$tmp/elem_none_first.ae" 2>&1 | tail -1)"
if [ "$got" != "3 -1 -1 3" ]; then
    echo "  [FAIL] array_literal_element_type: none beside an optional, either side, gave '$got'"
    fail=1
fi

cat > "$tmp/elem_none_int.ae" <<'AE'
main() {
    xs = [ 1, none ]
    println("${xs.len}")
}
AE
expect_error "$tmp/elem_none_int.ae" "array literal element 2 is \`none\`, which an array of 'int' cannot hold" "none in an int array literal was not refused"

# The explicit forms stay legal: an annotated int slot narrows on purpose.
cat > "$tmp/explicit.ae" <<'AE'
main() {
    int k = 4.5
    int[2] xs = [ 1, 2 ]
    xs[0] = 7.5
    println("${k} ${xs[0]}")
}
AE
got="$(AETHER_HOME="$ROOT" "$AE" run "$tmp/explicit.ae" 2>&1 | tail -1)"
if [ "$got" != "4 7" ]; then
    echo "  [FAIL] array_literal_element_type: the annotated narrowing forms no longer compile (got '$got')"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "  [PASS] array_literal_element_type: literals join their element types; inferred-int narrowing, nested literals and elements the type cannot hold are refused"
fi
exit $fail
