#!/bin/sh
# A match arm's struct pattern is checked as a clause head's (#2992).
#
# The arm `Pt { x: 0, y: _ }` was read as a struct literal ("Undefined
# variable '_'"). It is a struct pattern now, through the clause head's
# checks (#2988): a field the struct does not have, a literal of another
# type than its field, and a value matched that is not the pattern's struct
# are errors at the arm. A struct pattern with a literal field takes only
# some values of its struct, so a match whose arms all test a field and has
# no `_` may run no arm: a function that returns from each arm can still
# reach its end (E0700), while one whose last arm tests nothing cannot.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] match_struct_pattern_reject: aetherc not built"
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
            echo "  [FAIL] match_struct_pattern_reject: no diagnostic matching: $want"
            printf '%s\n' "$out" | grep -E "^error|-->" | head -8 | sed 's/^/        |/'
            fail=1
        fi
    done
}

cat > "$tmp/bad.ae" <<'AE'
struct Pt {
    x: int
    y: int
}

a(p: Pt) -> int {
    return match p {
        Pt { z: 0 } -> 1
        _ -> 2
    }
}

b(p: Pt) -> int {
    return match p {
        Pt { x: "no", y: _ } -> 1
        _ -> 2
    }
}

c(n: int) -> int {
    return match n {
        Pt { x: 0, y: _ } -> 1
        _ -> 2
    }
}

main() {
    println("${a(Pt { x: 1, y: 2 })}")
}
AE
check_errors bad.ae \
    "bad.ae:8:[0-9]* .*'Pt' has no field 'z'" \
    "bad.ae:15:[0-9]* .*field 'x' of 'Pt' is int, and the pattern gives it string" \
    "bad.ae:22:[0-9]* .*a struct pattern of 'Pt' matches a 'Pt', and the value matched is an int"

cat > "$tmp/cover.ae" <<'AE'
struct Pt {
    x: int
    y: int
}

some_values(p: Pt) -> int {
    match p {
        Pt { x: 0, y: _ } -> {
            return 1
        }
        Pt { x: 1, y: b } -> {
            return b
        }
    }
}

every_value(p: Pt) -> int {
    match p {
        Pt { x: 0, y: _ } -> {
            return 1
        }
        Pt { x: a, y: _ } -> {
            return a
        }
    }
}

main() {
    println("${some_values(Pt { x: 1, y: 2 })} ${every_value(Pt { x: 1, y: 2 })}")
}
AE
check_errors cover.ae \
    "cover.ae:15:[0-9]* .*missing return: control can reach the end of 'some_values'"
out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/cover.ae" 2>&1)"
if printf '%s\n' "$out" | grep -q "every_value"; then
    echo "  [FAIL] match_struct_pattern_reject: a match ending in an arm that tests no field was taken to miss values"
    fail=1
fi

if [ $fail -eq 0 ]; then
    echo "  [PASS] match_struct_pattern_reject: arm struct patterns are checked, and only a pattern that tests no field covers its struct"
fi
exit $fail
