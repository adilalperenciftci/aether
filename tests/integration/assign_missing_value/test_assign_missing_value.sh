#!/bin/sh
# Regression (#2998): a statement that ends before its value must not compile.
#
# The expression parser returns nothing, without a word, at a token that
# cannot begin an expression (`}`, `;`, `)`, the end of the file), and each
# place that had already consumed an `=` or an operator took that as "no
# value": `main() { x = }` compiled (W1001 and "unresolved type in codegen,
# defaulting to int"), and so did `int x =`, `x = ;`, `y = x +`, `x = -`,
# `x = foo(`, `return 1 +` and `[1, , 2]`. A bare `return` in a function whose
# written result is a value reached C, which takes `return;` there with a
# warning (GCC 14 refuses it).
#
# Each malformed form must be refused with exactly one error, E0100 at the `=`
# or operator that wants the value (E0200 at the bare `return`), and the
# legitimate neighbours (a trailing comma in an array literal and in print, a
# bare `return` in a void function, a multi-value return, a default argument,
# a value continued on the next line after `=`) must still compile.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ] && [ ! -x "$AETHERC.exe" ]; then
    echo "  [SKIP] assign_missing_value: aetherc not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# refuse NAME WHERE CODE MESSAGE: the program in $TMP/NAME.ae is refused with
# one error, error[CODE] whose text contains MESSAGE, at WHERE (line:column).
refuse() {
    name="$1"; where="$2"; code="$3"; msg="$4"
    out="$("$AETHERC" --check "$TMP/$name.ae" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  [FAIL] $name: compiled"
        fail=1
        return
    fi
    errors=$(printf '%s\n' "$out" | grep -c '^error')
    first=$(printf '%s\n' "$out" | grep -m1 '^error')
    at=$(printf '%s\n' "$out" | grep -m1 -- '-->' | sed 's/.*\.ae://')
    case "$first" in
        "error[$code]: "*"$msg"*) ;;
        *)
            echo "  [FAIL] $name: expected error[$code] with \"$msg\", got: $first"
            fail=1
            return
            ;;
    esac
    if [ "$at" != "$where" ]; then
        echo "  [FAIL] $name: reported at $at, expected $where"
        fail=1
        return
    fi
    if [ "$errors" -ne 1 ]; then
        echo "  [FAIL] $name: expected 1 error, got $errors"
        printf '%s\n' "$out" | sed 's/^/        /' | head -20
        fail=1
        return
    fi
    echo "  [PASS] $name"
}

printf 'main() { x = }\n' > "$TMP/assign_brace.ae"
refuse assign_brace 1:12 E0100 'expected a value after `=`, found `}`'

printf 'main() {\n    x = 1\n    x = ;\n    println(x)\n}\n' > "$TMP/assign_semicolon.ae"
refuse assign_semicolon 3:7 E0100 'expected a value after `=`, found `;`'

printf 'main() {\n    int x =\n}\n' > "$TMP/typed_decl.ae"
refuse typed_decl 2:11 E0100 'expected a value after `=`'

printf 'main() {\n    var x =\n}\n' > "$TMP/var_decl.ae"
refuse var_decl 2:11 E0100 'expected a value after `=`'

printf 'main() {\n    let x: int =\n}\n' > "$TMP/let_typed.ae"
refuse let_typed 2:16 E0100 'expected a value after `=`'

printf 'main() {\n    x = 1\n    x +=\n}\n' > "$TMP/compound.ae"
refuse compound 3:7 E0100 'expected a value after `+=`'

printf 'struct P { x: int }\nmain() {\n    p = P { x: 1 }\n    p.x =\n}\n' > "$TMP/field_store.ae"
refuse field_store 4:9 E0100 'expected a value after `=`'

printf 'struct P { x: int }\nmain() {\n    p = P { x: 1 }\n    p.x -=\n}\n' > "$TMP/field_compound.ae"
refuse field_compound 4:9 E0100 'expected a value after `-=`'

printf 'main() {\n    xs = [1, 2]\n    xs[0] =\n}\n' > "$TMP/element_store.ae"
refuse element_store 3:11 E0100 'expected a value after `=`'

printf 'f() -> (int, int) {\n    return 1, 2\n}\nmain() {\n    a, b =\n}\n' > "$TMP/destructure.ae"
refuse destructure 5:10 E0100 'expected a value after `=`'

printf 'main() {\n    x = 1\n    y = x +\n}\n' > "$TMP/binary_operand.ae"
refuse binary_operand 3:11 E0100 'expected an operand after `+`, found `}`'

printf 'main() {\n    x = -\n}\n' > "$TMP/unary_operand.ae"
refuse unary_operand 2:9 E0100 'expected an operand after `-`'

printf 'f() -> int {\n    return 1 +\n}\nmain() {\n    println(f())\n}\n' > "$TMP/return_operand.ae"
refuse return_operand 2:14 E0100 'expected an operand after `+`'

printf 'f() -> (int, int) {\n    return 1,\n}\nmain() {\n    a, b = f()\n    println(a + b)\n}\n' > "$TMP/return_comma.ae"
refuse return_comma 2:13 E0100 'expected a value after `,`'

printf 'g(a: int) -> int {\n    return a\n}\nmain() {\n    x = g(\n}\n' > "$TMP/call_open.ae"
refuse call_open 5:10 E0100 'expected an argument or `)` after `(`'

printf 'main() {\n    xs = [1, , 2]\n    println(xs[0])\n}\n' > "$TMP/array_hole.ae"
refuse array_hole 2:12 E0100 'expected an element after `,`'

printf 'const LIMIT =\n' > "$TMP/const_eof.ae"
refuse const_eof 1:13 E0100 'expected a value after `=`, found the end of the file'

printf 'f() -> int {\n    return\n}\nmain() {\n    println(f())\n}\n' > "$TMP/bare_return.ae"
refuse bare_return 2:5 E0200 "'f' returns int, but this \`return\` gives no value"

# The forms that look alike and are fine.
cat > "$TMP/good.ae" <<'AEOF'
pair() -> (int, int) {
    return 1, 2
}

scale(n: int, by: int = 3) -> int {
    return n * by
}

stop(n: int) {
    if n > 1 {
        return
    }
    println("small")
}

main() {
    xs = [1, 2,]
    total =
        xs[0] + xs[1]
    a, b = pair()
    total += a + b
    print(total, )
    println("")
    stop(5)
    println(scale(2))
}
AEOF
if ! "$AETHERC" --check "$TMP/good.ae" >"$TMP/good.log" 2>&1; then
    echo "  [FAIL] good: a valid program stopped compiling"
    sed 's/^/        /' "$TMP/good.log" | head -10
    fail=1
else
    echo "  [PASS] good"
fi

exit $fail
