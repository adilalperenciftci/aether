#!/bin/sh
# #3022: `++` and `--`, prefix or postfix, change a number held in storage:
# a local, parameter, module `var` or actor state that is not a `const`, a
# field or an element, of an integer or float type. The only check was the
# #2516 one against a `const` table's element, so every other operand passed
# `ae check`: a literal, a call, an expression, a `const`, an array and a
# struct stopped at the C compiler ("lvalue required"), `b++` on a bool ran
# as C's _Bool arithmetic, and `s++` on a string moved its pointer (it
# printed from the wrong place, and a heap string was then released through
# an address it was never allocated at). Each row of the issue's table is
# refused here in both positions, with the message naming what the operand
# is, and so are the shapes found beside them: a string's character, which
# `s[i] = v` wrote too (#3022), an enum member, a distinct type, a pointer, a
# Duration, `ref_get(r)` and a field of a call's result. `---- 5` is one
# error, not two. The accepted forms run on the default C path and the
# strict C11 one.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then echo "  [SKIP] step_operand: $AE not built"; exit 0; fi
export AETHER_HOME="$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
CC_BIN="${CC:-cc}"
command -v "$CC_BIN" >/dev/null 2>&1 || CC_BIN=gcc
fail=0

# <name> <pattern the diagnostic must match>; the program is on stdin.
refused() {
    name="$1"; want="$2"
    cat > "$tmp/$name.ae"
    if "$AETHERC" "$tmp/$name.ae" "$tmp/$name.c" >"$tmp/$name.log" 2>&1; then
        echo "  [FAIL] step_operand: $name compiled (it must be refused before C)"
        fail=1; return
    fi
    if ! grep -qF "$want" "$tmp/$name.log"; then
        echo "  [FAIL] step_operand: $name refused, but not with: $want"
        sed 's/^/        /' "$tmp/$name.log" | head -6
        fail=1
    fi
}

stored="needs a number stored in a variable, a field or an element"

refused lit_pre "\`++\` $stored, and the operand is a literal" <<'AE'
main() {
    x = ++5
    println("${x}")
}
AE
refused lit_post "\`++\` $stored, and the operand is a literal" <<'AE'
main() {
    x = 5++
    println("${x}")
}
AE
refused lit_stmt "\`--\` $stored, and the operand is a literal" <<'AE'
main() {
    -- 5
}
AE
refused call_pre "and the result of 'f(...)' is a value, not storage" <<'AE'
f() -> int { return 3 }
main() {
    x = --f()
    println("${x}")
}
AE
refused call_post "and the result of 'f(...)' is a value, not storage" <<'AE'
f() -> int { return 3 }
main() {
    x = f()--
    println("${x}")
}
AE
refused paren_pre "\`++\` $stored, and the operand is an expression, not storage" <<'AE'
main() {
    y = 1
    x = ++(y + 1)
    println("${x}")
}
AE
refused paren_post "\`++\` $stored, and the operand is an expression, not storage" <<'AE'
main() {
    y = 1
    x = (y + 1)++
    println("${x}")
}
AE
refused const_pre "\`++\` $stored, and 'K' is a constant" <<'AE'
const K = 3
main() {
    x = ++K
    println("${x}")
}
AE
refused const_post "\`--\` $stored, and 'K' is a constant" <<'AE'
const K = 3
main() {
    K--
    println("${K}")
}
AE
refused array_pre "\`++\` steps an integer or a float, and 'a' has type int[2]" <<'AE'
main() {
    a = [1, 2]
    ++a
    println("${a[0]}")
}
AE
refused array_post "\`++\` steps an integer or a float, and 'a' has type int[2]" <<'AE'
main() {
    a = [1, 2]
    a++
    println("${a[0]}")
}
AE
refused struct_pre "\`--\` steps an integer or a float, and 'p' has type P" <<'AE'
struct P { x: int }
main() {
    p = P { x: 1 }
    --p
    println("${p.x}")
}
AE
refused struct_post "\`++\` steps an integer or a float, and 'p' has type P" <<'AE'
struct P { x: int }
main() {
    p = P { x: 1 }
    p++
    println("${p.x}")
}
AE
refused bool_pre "\`++\` steps an integer or a float, and 'b' has type bool" <<'AE'
main() {
    b = true
    ++b
    println("${b}")
}
AE
refused bool_post "\`++\` steps an integer or a float, and 'b' has type bool" <<'AE'
main() {
    b = true
    b++
    println("${b}")
}
AE
refused string_pre "\`--\` steps an integer or a float, and 's' has type string" <<'AE'
main() {
    s = "abc"
    --s
    println(s)
}
AE
refused string_post "\`++\` steps an integer or a float, and 's' has type string" <<'AE'
main() {
    s = "abc"
    s++
    println(s)
}
AE
refused heap_string "\`++\` steps an integer or a float, and 's' has type string" <<'AE'
import std.string
main() {
    s = string.concat("ab", "cd")
    s++
    println(s)
}
AE
refused string_char_step "cannot write to a character of 's': a string's bytes are read-only" <<'AE'
main() {
    s = "abc"
    s[0]++
    println(s)
}
AE
refused string_char_assign "cannot write to a character of 's': a string's bytes are read-only" <<'AE'
main() {
    s = "abc"
    s[0] = 66
    println(s)
}
AE
refused enum_member "\`++\` $stored, and 'Color.Red' is an enum member, a constant" <<'AE'
enum Color { Red, Green }
main() {
    Color.Red++
}
AE
refused distinct "\`++\` steps an integer or a float, and 'a' has type USD" <<'AE'
type USD = distinct float
main() {
    a = 1.5 as USD
    a++
    println("${a as float}")
}
AE
refused pointer "\`++\` steps an integer or a float, and 'p' has type ptr" <<'AE'
main() {
    ptr p = null
    p++
}
AE
refused duration "\`--\` steps an integer or a float, and 'd' has type Duration" <<'AE'
main() {
    d = 5ms
    d--
}
AE
refused ref_get "ref_set(r, ref_get(r) + 1)" <<'AE'
main() {
    r = ref(1)
    ref_get(r)++
    println("${ref_get(r)}")
}
AE
refused call_part "and this is a part of the result of 'mk(...)', a temporary" <<'AE'
struct P { x: int }
mk() -> P { return P { x: 1 } }
main() {
    mk().x++
}
AE
refused chain "\`--\` $stored, and the operand is a literal" <<'AE'
main() {
    x = ---- 5
    println("${x}")
}
AE
if [ -f "$tmp/chain.log" ] && [ "$(grep -c 'error\[' "$tmp/chain.log")" -ne 1 ]; then
    echo "  [FAIL] step_operand: \`---- 5\` must be one error, the inner \`--\` on the literal:"
    sed 's/^/        /' "$tmp/chain.log" | head -8
    fail=1
fi

# The accepted forms: a local in both positions, a float, an f32, a long, a
# byte, a field, an element, a module `var` and a parameter.
cat > "$tmp/accepted.ae" <<'AE'
struct P { x: int }

var g = 0

bump(n: int) -> int {
    n++
    return n
}

main() {
    y = 1
    y++
    --y
    old = y++
    f = 1.5
    f++
    p = P { x: 1 }
    p.x++
    a = [1, 2]
    a[0]++
    --a[1]
    long n = 5
    n--
    byte bb = 3
    bb++
    f32 h = 1.0
    h++
    g++
    println("${y} ${old} ${f} ${p.x} ${a[0]} ${a[1]} ${n} ${bb} ${h} ${g} ${bump(5)}")
}
AE
want="2 1 2.5 2 2 1 4 4 2 1 6"
for path in default nogcc; do
    cc=""
    [ "$path" = nogcc ] && cc="$CC_BIN -DAETHER_GCC_COMPAT=0"
    if ! AE_CC="$cc" "$AE" build "$tmp/accepted.ae" -o "$tmp/accepted_$path" >"$tmp/build.log" 2>&1; then
        echo "  [FAIL] step_operand: the accepted forms did not build ($path):"
        grep -m6 -iE "error" "$tmp/build.log" | sed 's/^/        /'
        fail=1; continue
    fi
    got="$("$tmp/accepted_$path" 2>&1 | tr -d '\r')"
    if [ "$got" != "$want" ]; then
        echo "  [FAIL] step_operand: the accepted forms printed '$got', want '$want' ($path)"
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] step_operand: ++ and -- refuse a literal, a call, an expression, a const, an array, a struct, a bool, a string, a string's character and the rest before C, in both positions; the accepted forms run on both C paths"
fi
exit "$fail"
