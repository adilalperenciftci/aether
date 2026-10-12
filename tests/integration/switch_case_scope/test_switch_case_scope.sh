#!/bin/sh
# Regression for #2732: each `switch` case is a scope of its own, in the type
# checker as in the C it lowers to.
#
# The checker took the cases for part of the enclosing scope, so a name first
# bound in one case and read where the C cannot see it passed `ae check` and
# failed in the C compiler ("'v' undeclared"). The reads the hoists make
# valid (tests/regression/test_switch_case_scope.ae) compile; these, which no
# hoist covers, are now the checker's "Undefined variable", as the same reads
# of a name bound in an `if` branch are.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] switch_case_scope: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# undefined <name> <line:col>: refused by the checker as an undefined name at
# that position, before the C compiler runs.
undefined() {
    name="$1"; at="$2"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $name: accepted"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    case "$out" in
        *"Undefined variable 'v'"*"$name.ae:$at"*) ;;
        *) echo "  [FAIL] $name: not \"Undefined variable 'v'\" at $at:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

# A switch nested in an if, where not every case binds the name.
cat > "$TMP/nested_partial.ae" <<'AE'
pick(x: int) -> int {
    if x > 0 {
        switch x {
            case 1: v = 10
            default: println("other")
        }
        return v
    }
    return 0
}
main() { println("${pick(1)}") }
AE
undefined nested_partial 7:16

# Every case binds it, but with no default some path binds nothing.
cat > "$TMP/nested_no_default.ae" <<'AE'
pick(x: int) -> int {
    if x > 0 {
        switch x {
            case 1: v = 10
            case 2: v = 20
        }
        return v
    }
    return 0
}
main() { println("${pick(1)}") }
AE
undefined nested_no_default 7:16

# A name one case binds, read in another.
cat > "$TMP/other_case.ae" <<'AE'
main() {
    x = 2
    switch x {
        case 1: v = 10
        case 2: println("${v}")
    }
}
AE
undefined other_case 5:28

[ "$fails" -eq 0 ] || exit 1
echo "  [PASS] switch_case_scope: a case binds its names in its own scope"
