#!/bin/sh
# A closure compares only with `null` (#3067, Go's rule for function values):
# `==` and `!=` between two closures, or a closure and anything else, are
# E0200. Two closures have no equality worth giving (the same function over
# another environment is another closure), and codegen gives the comparison
# a meaning only against `null`: the rest passed the checker and C refused
# it, `invalid operands to binary ==`. What `c == null` computes, and `null`
# in an array literal of closures, is in tests/regression
# (test_issue3062_closure_null.ae, test_issue3067_closure_null_array.ae).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] closure_compare_null: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# refused <name> <text> <line:col>: `ae check` refuses <name>.ae with an
# E0200 whose message holds <text>, at that position.
refused() {
    out=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" check "$1.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $1: accepted"
        fails=$((fails + 1))
        return
    fi
    case "$out" in
        *"error[E0200]"*"$2"*"$1.ae:$3"*) ;;
        *) echo "  [FAIL] $1: not E0200 \"$2\" at $3"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

cat > "$TMP/two_closures_eq.ae" <<'AE'
adder(n: int) -> fn {
    return | x: int | -> x + n
}

main() {
    f = adder(1)
    g = adder(2)
    println("${f == g}")
}
AE
refused two_closures_eq "'==' compares two closures: a closure compares only with \`null\`" 8:18

cat > "$TMP/two_closures_ne.ae" <<'AE'
main() {
    k = 3
    f = | x: int | -> x + k
    g = | x: int | -> x * k
    if f != g { println("apart") }
}
AE
refused two_closures_ne "'!=' compares two closures" 5:10

cat > "$TMP/closure_ptr.ae" <<'AE'
same(f: fn, p: ptr) -> bool {
    return f == p
}

main() { println("x") }
AE
refused closure_ptr "'==' compares a closure with 'ptr': a closure compares only with \`null\`" 2:14

cat > "$TMP/ptr_closure.ae" <<'AE'
apart(p: ptr, f: fn) -> bool {
    return p != f
}

main() { println("x") }
AE
refused ptr_closure "'!=' compares a closure with 'ptr'" 2:14

# A struct's closure fields (a moded type is a closure, #2980).
# A typed `fn(int) -> int` is a C function pointer, which C compares.
cat > "$TMP/field_closure.ae" <<'AE'
struct Slot { build: fn(@keep ptr, int) -> int }

main() {
    k = 2
    s = Slot { build: | p: @keep ptr, x: int | -> x + k }
    t = Slot { build: | p: @keep ptr, x: int | -> x - k }
    println("${s.build == t.build}")
}
AE
refused field_closure "'==' compares two closures" 7:24

# Against `null` it is what #3062 made it: it compiles and runs.
cat > "$TMP/with_null.ae" <<'AE'
main() {
    k = 3
    f = | x: int | -> x + k
    println("${f == null} ${null != f}")
}
AE
got=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run with_null.ae 2>&1)
if [ "$got" != "false true" ]; then
    echo "  [FAIL] with_null: a closure against null printed '$got'"
    fails=$((fails + 1))
fi

# A typed C function pointer holds no environment: two compare as C's
# pointers do, and a named function is one.
cat > "$TMP/fnptrs.ae" <<'AE'
twice(x: int) -> int { return x * 2 }
thrice(x: int) -> int { return x * 3 }
is_twice(f: fn(int) -> int) -> bool { return f == twice }
same(f: fn(int) -> int, g: fn(int) -> int) -> bool { return f == g }

main() {
    println("${is_twice(twice)} ${is_twice(thrice)} ${same(twice, twice)} ${same(twice, thrice)}")
}
AE
got=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run fnptrs.ae 2>&1)
if [ "$got" != "true false true false" ]; then
    echo "  [FAIL] fnptrs: typed function pointers compared printed '$got'"
    fails=$((fails + 1))
fi

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] closure_compare_null: a closure compares only with null; two closures, or a closure and a pointer, are refused"
