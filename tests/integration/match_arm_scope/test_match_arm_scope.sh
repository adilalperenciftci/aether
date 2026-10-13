#!/bin/sh
# Regression for #2768: a name a `match` arm binds is one variable with the
# rest of the function exactly where a name an `if` branch binds would be.
#
# The reads the hoists make valid compile (tests/regression/
# test_match_arm_scope.ae; the issue's shape is checked here too). These,
# which no hoist covers, stay the checker's "Undefined variable", as the same
# reads of a name an `if` branch binds are, and never reach the C compiler:
# among them a name an arm's pattern binds, which no hoist takes out of the
# match (tests/regression/test_match_pattern_binding.ae has the arm's side).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] match_arm_scope: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# The issue's program: every arm binds `v`, a `_` arm runs for the rest.
cat > "$TMP/every_arm.ae" <<'AE'
pick(x: int) -> int {
    match x {
        1 -> { v = 10 }
        _ -> { v = 20 }
    }
    return v
}
main() { println("${pick(1)} ${pick(2)}") }
AE
out=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run every_arm.ae 2>&1)
case "$out" in
    *"10 20"*) ;;
    *) echo "  [FAIL] every_arm: not \"10 20\":"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

# undefined <file> <name> <line:col>: refused by the checker as an undefined
# name at that position, before the C compiler runs.
undefined() {
    file="$1"; name="$2"; at="$3"
    out=$(cd "$TMP" && "$AE" check "$file.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $file: accepted"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    case "$out" in
        *"Undefined variable '$name'"*"$file.ae:$at"*) ;;
        *) echo "  [FAIL] $file: not \"Undefined variable '$name'\" at $at:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

# Nested in an if, every arm binds it, but with no `_` some value runs no arm.
cat > "$TMP/nested_no_wildcard.ae" <<'AE'
pick(x: int) -> int {
    if x > 0 {
        match x {
            1 -> { v = 10 }
            2 -> { v = 20 }
        }
        return v
    }
    return 0
}
main() { println("${pick(1)}") }
AE
undefined nested_no_wildcard v 7:16

# Nested, and one arm binds nothing.
cat > "$TMP/nested_partial.ae" <<'AE'
pick(x: int) -> int {
    if x > 0 {
        match x {
            1 -> { v = 10 }
            _ -> { println("other") }
        }
        return v
    }
    return 0
}
main() { println("${pick(1)}") }
AE
undefined nested_partial v 7:16

# A match whose value is bound keeps its arms' names in the arms.
cat > "$TMP/value_match.ae" <<'AE'
main() {
    x = 3
    k = match x {
        3 -> {
            z = 4
            z * 2
        }
        _ -> {
            z = 1
            z
        }
    }
    println("${k} ${z}")
}
AE
undefined value_match z 13:21

# A name one arm binds, read in another.
cat > "$TMP/other_arm.ae" <<'AE'
main() {
    x = 2
    match x {
        1 -> { v = 10 }
        _ -> { println("${v}") }
    }
}
AE
undefined other_arm v 5:27

# A name an arm's pattern binds is that arm's own, and no hoist takes it out
# of the match from any arm: in the `some(v)` arm `v = v + 1` rebinds the
# pattern's value. Hoisted, the outer `v` shadowed it there and the read
# after the match got 0.
cat > "$TMP/pattern_some.ae" <<'AE'
pick(o: int?) -> int {
    if true {
        match o {
            some(v) -> { v = v + 1 }
            none -> { v = 0 }
        }
        return v
    }
    return -1
}
main() { println("${pick(41)}") }
AE
undefined pattern_some v 7:16

cat > "$TMP/pattern_cons.ae" <<'AE'
first(xs: int[]) -> int {
    if true {
        match xs {
            [] -> { hd = -1 }
            [hd | tl] -> { hd = hd * 2 }
        }
        return hd
    }
    return 0
}
main() {
    let a: int[2] = [5, 6]
    println("${first(a)}")
}
AE
undefined pattern_cons hd 7:16

# At the top of the function body too: the `none` arm's `v` is not hoisted
# for the read after the match while the `some(v)` arm binds its own.
cat > "$TMP/pattern_top.ae" <<'AE'
top(o: int?) -> int {
    match o {
        some(v) -> { println("got ${v}") }
        none -> { v = 7 }
    }
    return v
}
main() { println("${top(3)}") }
AE
undefined pattern_top v 6:12

[ "$fails" -eq 0 ] || exit 1
echo "  [PASS] match_arm_scope: a match arm's names hoist as an if branch's do"
