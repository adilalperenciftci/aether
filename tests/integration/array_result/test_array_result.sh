#!/bin/sh
# A named function returns a fixed-size array, alone or at a position of a
# tuple (#2894; #2886 refused it). C returns no array, so the function returns
# it in a struct of its own and every use takes the elements out: a binding
# moves them in, a struct field or a tuple position takes them, and a call used
# as an array (indexed, passed on) is held until its statement is done. Owning
# elements follow the model: the returned array hands its caller a reference to
# each, and the binding releases them at its exit.
#
# A closure, an extern and a function type still return no array (E0201): C
# gives an extern no array result, and a closure's or a function value's
# result has no struct to carry one.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EXE=""
[ -x "$ROOT/build/ae" ] || EXE=".exe"
AE="$ROOT/build/ae$EXE"
AETHERC="$ROOT/build/aetherc$EXE"
if [ ! -x "$AE" ] || [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] array_result: compiler not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# runs <name> <expected output>
runs() {
    name="$1"; want="$2"
    if ! ( cd "$TMP" && "$AE" build "$name.ae" -o "$TMP/$name" ) > "$TMP/$name.log" 2>&1; then
        echo "  [FAIL] array_result: $name did not build"
        grep -m5 "error" "$TMP/$name.log" | cut -c1-200 | sed 's/^/        /'
        fail=1
        return
    fi
    got="$("$TMP/$name$EXE" 2>&1 | tr -d '\r')"
    if [ "$got" != "$want" ]; then
        echo "  [FAIL] array_result: $name printed '$got', not '$want'"
        fail=1
    fi
}

# refused <name> <expected message part> <expected array in the help>
refused() {
    name="$1"; want="$2"; arr="$3"
    if "$AETHERC" "$TMP/$name.ae" "$TMP/$name.c" > "$TMP/$name.log" 2>&1; then
        echo "  [FAIL] array_result: $name compiled (should be refused)"
        fail=1
        return
    fi
    if ! grep -q "error\[E0201\]: $want" "$TMP/$name.log"; then
        echo "  [FAIL] array_result: $name not refused with E0201 '$want'"
        grep -m3 "error" "$TMP/$name.log" | cut -c1-200 | sed 's/^/        /'
        fail=1
        return
    fi
    if ! grep -qF "help: return it from a named function, or wrap it in a struct: struct Pair { v: $arr }" "$TMP/$name.log"; then
        echo "  [FAIL] array_result: $name refused without the help naming $arr"
        grep -m3 "help" "$TMP/$name.log" | cut -c1-200 | sed 's/^/        /'
        fail=1
    fi
}

cat > "$TMP/written.ae" <<'AE'
pair() -> int[2] {
    return [1, 2]
}

sum(xs: int[2]) -> int {
    return xs[0] + xs[1]
}

main() {
    a = pair()
    println("${a[0]} ${a[1]} ${pair()[1]} ${sum(pair())}")
}
AE
runs written "1 2 2 3"

cat > "$TMP/inferred.ae" <<'AE'
from_local() {
    int[2] a = [4, 5]
    return a
}

from_literal() {
    return [6, 7]
}

main() {
    a = from_local()
    b = from_literal()
    println("${a[0]} ${a[1]} ${b[0]} ${b[1]}")
}
AE
runs inferred "4 5 6 7"

cat > "$TMP/struct_elements.ae" <<'AE'
import std.string

struct Doc {
    name: string
    n: int
}

struct Row {
    docs: Doc[2]
}

two(w: string) -> Doc[2] {
    return [Doc { name: string.concat(w, "#0"), n: 0 }, Doc { name: string.concat(w, "#1"), n: 1 }]
}

main() {
    r = Row { docs: two("w") }
    d = two("v")
    println("${r.docs[0].name} ${r.docs[1].n} ${d[1].name}")
}
AE
runs struct_elements "w#0 1 v#1"

cat > "$TMP/tuples.ae" <<'AE'
import std.string

written() -> (string[2], int) {
    string[2] a = [string.concat("a", "0"), string.concat("a", "1")]
    return a, 3
}

inferred() {
    return [string.concat("b", "0"), string.concat("b", "1")], 4
}

main() {
    a, n = written()
    t = inferred()
    b, m = t
    _, k = written()
    println("${a[0]} ${a[1]} ${n} ${b[1]} ${m} ${k}")
}
AE
runs tuples "a0 a1 3 b1 4 3"

cat > "$TMP/closure.ae" <<'AE'
main() {
    g = || {
        int[2] a = [1, 2]
        return a
    }
    a = g()
    println("${a[0]}")
}
AE
refused closure "this closure returns int\[2\], a fixed-size array" "int[2]"

cat > "$TMP/extern.ae" <<'AE'
extern pair_c() -> int[2]

main() {
    println("x")
}
AE
refused extern "extern 'pair_c' returns int\[2\], a fixed-size array" "int[2]"

cat > "$TMP/fn_param.ae" <<'AE'
run(g: fn() -> int[2]) -> int {
    return 0
}

main() {
    println("${run(null)}")
}
AE
refused fn_param "parameter 'g' holds the function type .* which returns int\[2\]" "int[2]"

cat > "$TMP/fn_field.ae" <<'AE'
struct Maker {
    factory: fn() -> int[3]
}

main() {
    println("x")
}
AE
refused fn_field "struct field 'factory' holds the function type .* which returns int\[3\]" "int[3]"

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "  [PASS] array_result: a named function returns a fixed-size array, alone or in a tuple; a closure, an extern and a function type are refused (E0201)"
exit 0
