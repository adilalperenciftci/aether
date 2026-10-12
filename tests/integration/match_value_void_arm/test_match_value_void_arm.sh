#!/bin/sh
# Regression for #2743: a `match` whose value is used, with an arm that calls
# a function returning nothing, is a type error at that arm.
#
# The match takes its value from the arm that runs. An arm ending in a call of
# a function that returns nothing has none, and codegen stored the call's void
# in the match's result: the C compiler stopped with "void value not ignored".
# PR #2721 settled a `match` none of whose arms gives a value (it is the
# statement); a mixed one is refused here, at the arm, naming the call, for a
# match that is returned, bound, or the arm of one of those. An arm that ends
# in a statement (a `return`, a print) still gives no value and is accepted,
# and so is a match whose value nothing reads.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] match_value_void_arm: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# refused <name> <line:col>: rejected by the checker at that position, with
# the diagnostic and its help line, before the C compiler runs.
refused() {
    name="$1"; at="$2"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $name: accepted"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    case "$out" in
        *"'note' returns no value, so this arm gives the \`match\` none, and the value of the \`match\` is used"*) ;;
        *) echo "  [FAIL] $name: not the void-arm diagnostic:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)); return ;;
    esac
    case "$out" in
        *"help: give the arm a value: a block arm can make the call and end with one"*) ;;
        *) echo "  [FAIL] $name: no help line:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)); return ;;
    esac
    case "$out" in
        *"$name.ae:$at"*) ;;
        *) echo "  [FAIL] $name: not reported at $at:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

# The issue's shape: a returned match, one arm a void call.
cat > "$TMP/returned.ae" <<'AE'
note(x: int) { println("note ${x}") }

pick(n: int) -> int {
    return match n {
        1 -> note(1)
        _ -> 5
    }
}

main() {
    println("${pick(2)}")
}
AE
refused returned 5:14

# An arrow body whose last statement is such a match returns its value.
cat > "$TMP/arrow.ae" <<'AE'
note(x: int) { println("note ${x}") }

pick(n: int) -> {
    match n {
        1 -> 7
        _ -> note(n)
    }
}

main() {
    println("${pick(2)}")
}
AE
refused arrow 6:14

# A bound match.
cat > "$TMP/bound.ae" <<'AE'
note(x: int) { println("note ${x}") }

main() {
    n = 2
    v = match n {
        1 -> 10
        _ -> { note(n) }
    }
    println("${v}")
}
AE
refused bound 7:16

# The arm of a match that is the arm of a bound one.
cat > "$TMP/nested.ae" <<'AE'
note(x: int) { println("note ${x}") }

main() {
    n = 2
    v = match n {
        1 -> 10
        _ -> {
            match n {
                2 -> note(2)
                _ -> 30
            }
        }
    }
    println("${v}")
}
AE
refused nested 9:22

# Accepted: an arm that leaves with a `return`, and a match whose value
# nothing reads.
cat > "$TMP/accepted.ae" <<'AE'
note(x: int) { println("note ${x}") }

pick(n: int) -> int {
    v = match n {
        1 -> 10
        _ -> { return -1 }
    }
    return v
}

main() {
    n = 2
    match n {
        1 -> 10
        _ -> note(n)
    }
    println("${pick(1)} ${pick(2)}")
}
AE
out=$(cd "$TMP" && "$AE" run accepted.ae 2>&1)
if [ "$out" != "note 2
10 -1" ]; then
    echo "  [FAIL] accepted: gave [$out], want note 2 then 10 -1"
    fails=$((fails + 1))
fi

# The arm `1 -> 10` of the match nothing reads drops its value, and its C
# says so: it was the statement `10;`, which clang warns about by default, so
# `ae run` printed a C warning for a correct program on macOS. gcc reports
# the same with -Wunused-value, so the check runs on every C compiler.
AETHERC="$ROOT/build/aetherc"
[ -f "$AETHERC.exe" ] && AETHERC="$AETHERC.exe"
CC_BIN="${CC:-cc}"
command -v "$CC_BIN" >/dev/null 2>&1 || CC_BIN=gcc
INC="-I$ROOT -I$ROOT/runtime -I$ROOT/runtime/utils -I$ROOT/runtime/actors -I$ROOT/runtime/config -I$ROOT/runtime/scheduler -I$ROOT/runtime/memory -I$ROOT/std -I$ROOT/std/collections -I$ROOT/std/string"
if ! "$AETHERC" "$TMP/accepted.ae" "$TMP/accepted.c" >"$TMP/aetherc.log" 2>&1; then
    echo "  [FAIL] accepted: aetherc failed"
    sed 's/^/        /' "$TMP/aetherc.log" | head -10
    fails=$((fails + 1))
elif ! "$CC_BIN" -fsyntax-only -Werror=unused-value $INC "$TMP/accepted.c" >"$TMP/cc.log" 2>&1; then
    echo "  [FAIL] accepted: its C computes a value nothing uses"
    sed 's/^/        /' "$TMP/cc.log" | head -10
    fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] || exit 1
echo "  [PASS] match_value_void_arm: a void-call arm of a match whose value is used is refused"
