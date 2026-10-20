#!/bin/sh
# Regression (#3026): a module `var` is never a compile-time value.
#
# A `var` is parsed into the node a `const` is (#701), and the compile-time
# evaluator resolved both, so every user of it read a variable as frozen at
# its initializer: a `requires` on a `var` that starts true was dropped from
# the C (and never checked, whatever the variable held at the call), one on
# a `var` that starts false refused a correct program, the missing-return
# check accepted a function whose only `return` sat behind `if !flag`, and
# W1002 called the code after `if !flag { return }` unreachable (ae3d's
# warnings-as-errors builds failed on it).
#
# Also checked, the W1002 rule for a constant: an `if` on a `const` does not
# make the code after it unreachable (a flag disables code on purpose), but a
# loop on a true `const` with no `break` still never ends.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] var_not_constant: ae not built"; exit 0; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP" || :; return 0; }
trap cleanup EXIT
fail=0

# check_says NAME WANT: `ae check` of NAME.ae reports WANT (a code, such as
# W1002 or E0700, or "nothing": it passes with no diagnostic at all).
check_says() {
    out="$("$AE" check "$TMP/$1.ae" 2>&1)"
    rc=$?
    if [ "$2" = nothing ]; then
        if [ "$rc" -ne 0 ] || printf '%s\n' "$out" | grep -qE '(warning|error)\['; then
            echo "  [FAIL] $1: expected a clean check, got (exit $rc):"
            printf '%s\n' "$out" | head -6 | sed 's/^/        /'
            fail=1
            return
        fi
    elif ! printf '%s\n' "$out" | grep -q "\[$2\]"; then
        echo "  [FAIL] $1: expected $2, got:"
        printf '%s\n' "$out" | head -6 | sed 's/^/        /'
        fail=1
        return
    fi
    echo "  [PASS] $1: check says $2"
}

# runs NAME WANT: `ae run` of NAME.ae prints WANT as its last line.
runs() {
    got="$("$AE" run "$TMP/$1.ae" 2>&1 | tr -d '\r' | tail -1)"
    if [ "$got" = "$2" ]; then
        echo "  [PASS] $1: prints '$2'"
    else
        echo "  [FAIL] $1: expected '$2', got '$got'"
        fail=1
    fi
}

cat > "$TMP/if_var.ae" <<'EOF'
var g_on = false

turn_on() { g_on = true }

f(x: int) -> int {
    if !g_on || x == 0 { return 0 }
    return x
}

main() {
    turn_on()
    println("${f(3)}")
}
EOF
check_says if_var nothing
runs if_var 3

cat > "$TMP/while_var.ae" <<'EOF'
var g_run = true

main() {
    i = 0
    n = 0
    while g_run {
        if i == 1 { g_run = false }
        i = i + 1
        n = n + 1
    }
    println("done after ${n}")
}
EOF
check_says while_var nothing
runs while_var "done after 2"

cat > "$TMP/if_const.ae" <<'EOF'
const DEBUG = false

f(x: int) -> int {
    if !DEBUG { return 0 }
    return x
}

main() {
    println("${f(3)}")
}
EOF
check_says if_const nothing
runs if_const 0

cat > "$TMP/while_const.ae" <<'EOF'
const RUN = true

main() {
    n = 0
    while RUN {
        n = n + 1
    }
    println("never")
}
EOF
check_says while_const W1002

cat > "$TMP/return_var.ae" <<'EOF'
var g_flag = false

f() -> int {
    if !g_flag { return 1 }
}

main() {
    println("${f()}")
}
EOF
check_says return_var E0700

cat > "$TMP/requires_true.ae" <<'EOF'
var g_ok = true

needs(x: int) -> int
    requires g_ok
{
    return x
}

main() {
    g_ok = false
    println("got ${needs(3)}")
}
EOF
out="$("$AE" run "$TMP/requires_true.ae" 2>&1 | tr -d '\r')"
if printf '%s\n' "$out" | grep -q "precondition_violation: g_ok in needs"; then
    echo "  [PASS] requires_true: the precondition is checked when the call runs"
else
    echo "  [FAIL] requires_true: expected the precondition to fail at run time, got:"
    printf '%s\n' "$out" | head -4 | sed 's/^/        /'
    fail=1
fi

cat > "$TMP/requires_false.ae" <<'EOF'
var g_ok = false

needs(x: int) -> int
    requires g_ok
{
    return x
}

main() {
    g_ok = true
    println("got ${needs(3)}")
}
EOF
check_says requires_false nothing
runs requires_false "got 3"

exit $fail
