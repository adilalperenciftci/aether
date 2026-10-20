#!/bin/sh
# Regression: a value taken from a call that gives none.
#
# Only a local's initializer was checked (`x = g()`, with g returning
# nothing, is E0200), and only for a callee named without its module. Every
# other place that takes the value reached C, which refused it as an
# "invalid use of void expression": a field or element store, an argument,
# an operand, an interpolation, an array, tuple or struct literal, an index,
# a compound assignment. And `x = print(1)` compiled, reading whatever the
# generated code left. Found while fixing #2998 (`x =` with the value on the
# next line). Each is now E0200 at the call, naming it and the place.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ]; then
    echo "  [SKIP] value_of_nothing: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# refuse NAME WHERE TEXT BODY: main's BODY, beside a void g, a struct P and
# h(a: int), is refused with one E0200 containing TEXT at WHERE.
refuse() {
    name="$1"; where="$2"; text="$3"; body="$4"
    printf 'struct P { a: int }\ng() {\n    println("g")\n}\nh(a: int) {\n    println(a)\n}\nmain() {\n%b\n}\n' \
        "$body" > "$TMP/$name.ae"
    out="$("$AE" check "$TMP/$name.ae" 2>&1)"
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $name: compiled"
        fail=1
        return
    fi
    first=$(printf '%s\n' "$out" | grep -a -m1 '^error')
    at=$(printf '%s\n' "$out" | grep -a -m1 -- '-->' | sed 's/.*\.ae://')
    errors=$(printf '%s\n' "$out" | grep -a -c '^error')
    case "$first" in
        "error[E0200]: "*"$text"*) ;;
        *)
            echo "  [FAIL] $name: expected E0200 with \"$text\", got: $first"
            fail=1
            return
            ;;
    esac
    if [ "$at" != "$where" ] || [ "$errors" -ne 1 ]; then
        echo "  [FAIL] $name: $errors error(s), first at $at, expected one at $where"
        fail=1
        return
    fi
    echo "  [PASS] $name"
}

refuse field_store 10:11 "'g' returns no value, so there is nothing to assign here" \
    '    p = P { a: 1 }\n    p.a = g()\n    println(p.a)'
refuse element_store 10:13 "nothing to assign here" \
    '    xs = [1, 2]\n    xs[0] = g()\n    println(xs[0])'
refuse argument 9:7 "'g' returns no value, so there is nothing to pass here" \
    '    h(g())'
refuse operand 9:13 "nothing to use here" \
    '    x = 1 + g()\n    println(x)'
refuse unary 9:10 "nothing to use here" \
    '    x = -g()\n    println(x)'
refuse print_arg 9:13 "nothing to print here" \
    '    println(g())'
refuse interpolation 9:14 "nothing to interpolate here" \
    '    s = "v=${g()}"\n    println(s)'
refuse array_element 9:11 "nothing to store here" \
    '    xs = [g()]\n    println(xs[0])'
refuse tuple_element 9:10 "nothing to store here" \
    '    t = (g(), 1)'
refuse struct_field 9:16 "nothing to store here" \
    '    p = P { a: g() }\n    println(p.a)'
refuse index 10:16 "nothing to index with here" \
    '    xs = [1, 2]\n    println(xs[g()])'
refuse compound 10:10 "nothing to use here" \
    '    x = 1\n    x += g()\n    println(x)'
refuse print_value 9:9 "'print' returns no value, so there is nothing to assign here" \
    '    x = print(1)\n    println(x)'

# The places a call with no value belongs still compile.
cat > "$TMP/good.ae" <<'AEOF'
g() {
    println("g")
}

f(n: int) {
    if n > 1 {
        return g()
    }
    defer g()
    g()
    match n {
        1 -> g()
        _ -> println("other")
    }
    run = || { g() }
    call(run)
}

main() {
    f(1)
    f(2)
}
AEOF
if out="$("$AE" run "$TMP/good.ae" 2>&1)"; then
    echo "  [PASS] good"
else
    echo "  [FAIL] good: a valid program stopped compiling:"
    printf '%s\n' "$out" | sed 's/^/        /' | head -10
    fail=1
fi

exit $fail
