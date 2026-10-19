#!/bin/sh
# A `match` used as an operand gives a value on every path that reaches the
# expression around it (#2993).
#
# A `match` is an expression now, where it was a statement the parser could
# not read as one: `b = b + match i { ... }` dropped the sum, and `c = 1 +
# match b { ... }` declared `c` uninitialized. A bound or returned `match`
# falls back on its variable or its `return`; an operand has nothing to
# fall back on, so the checker refuses one that runs no arm for some values
# (no `_`, and arms that do not cover the subject's type) and an arm that
# ends in a statement, unless the arm leaves (`return`, `break`, `continue`,
# `panic`). The same program written with `_` and values builds.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] match_operand_reject: aetherc not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0

check_errors() {  # file, then the "file:line:col message" patterns it must report
    f="$1"
    shift
    out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/$f" 2>&1)"
    for want in "$@"; do
        if ! printf '%s\n' "$out" | awk '/^error/ { m = $0; next } /-->/ && m != "" { print $2 " " m; m = "" }' | grep -q "$want"; then
            echo "  [FAIL] match_operand_reject: no diagnostic matching: $want"
            printf '%s\n' "$out" | grep -E "^error|-->" | head -8 | sed 's/^/        |/'
            fail=1
        fi
    done
}

cat > "$tmp/bad.ae" <<'AE'
main() {
    b = 3
    c = 1 + match b {
        0 -> 5
    }
    d = 1 + match b {
        0 -> { b = 1 }
        _ -> 2
    }
    println("${c} ${d}")
}
AE
check_errors bad.ae \
    "bad.ae:3:[0-9]* .*runs no arm for some values of what it matches" \
    "bad.ae:7:[0-9]* .*this arm gives the .match. no value, and the .match. is used as one"

cat > "$tmp/good.ae" <<'AE'
f(b: int) -> int {
    i = 0
    while i < 10 {
        i = i + match b {
            0 -> { break }
            1 -> { return 99 }
            _ -> 1
        }
    }
    return i
}

main() {
    b = 3
    c = 1 + match b {
        0 -> 5
        _ -> 6
    }
    let o: int? = 2
    d = 1 + match o {
        some(v) -> v
        none -> 0
    }
    println("${c} ${d} ${f(2)}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/good.ae" 2>&1)"
if printf '%s\n' "$out" | grep -q "^error"; then
    echo "  [FAIL] match_operand_reject: a match operand that gives a value on every path was refused"
    printf '%s\n' "$out" | grep -E "^error|-->" | head -8 | sed 's/^/        |/'
    fail=1
fi

if [ $fail -eq 0 ]; then
    echo "  [PASS] match_operand_reject: a match operand must give a value on every path that reaches its expression"
fi
exit $fail
