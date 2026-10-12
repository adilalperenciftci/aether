#!/bin/sh
# Regression for #2727: a `match` arm or a `switch` case is checked against
# the value it compares.
#
# Nothing checked an arm's pattern against the value matched when that value
# was not an enum, a sum or an optional; codegen emitted `_match_val ==
# <pattern>` and the C compiler met the mistake. An arm naming no variable was
# "'other' undeclared" at a misplaced line, a string arm over an int compared a
# pointer with an integer and never matched, and a literal arm over an
# optional or a sum was dropped without a word. Each shape below is now a
# checker error at the arm, naming what is wrong and how to write it; the
# program never reaches the C compiler.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] match_arm_pattern_check: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0

# expect <name> <message fragment> <help fragment>: the file must be refused
# by the checker with both fragments, and the C compiler must not run.
expect() {
    name="$1"; want="$2"; help="$3"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  [FAIL] $name: accepted"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    case "$out" in
        *"$want"*) ;;
        *) echo "  [FAIL] $name: no '$want' in:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)); return ;;
    esac
    case "$out" in
        *"help: $help"*) ;;
        *) echo "  [FAIL] $name: no help line '$help' in:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)); return ;;
    esac
    case "$out" in
        *"undeclared (first use"*|*"pointer and integer"*)
           echo "  [FAIL] $name: reached the C compiler:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

cat > "$TMP/undeclared.ae" <<'AE'
main() {
    n = 2
    match n {
        1 -> println("one")
        other -> println("other")
    }
}
AE
expect undeclared "'other' names no variable: a match arm compares the value matched" \
    "write \`_\` to take every other value"

cat > "$TMP/string_arm.ae" <<'AE'
main() {
    n = 2
    match n {
        1 -> println("one")
        "two" -> println("two")
        _ -> println("other")
    }
}
AE
expect string_arm "this match arm compares the value matched (int) with \"two\", a string" \
    "write a value of type int here"

cat > "$TMP/string_var.ae" <<'AE'
main() {
    n = 2
    s = "two"
    match n {
        s -> println("two")
        _ -> println("other")
    }
}
AE
expect string_var "compares the value matched (int) with 's', a string" \
    "write a value of type int here"

cat > "$TMP/opt_literal.ae" <<'AE'
main() {
    let m: int? = 5
    match m {
        5 -> println("five")
        none -> println("none")
        some(v) -> println("some ${v}")
    }
}
AE
expect opt_literal "a match over an optional takes \`none\`, \`some(name)\` and \`_\` arms" \
    "bind the value with \`some(v)\`"

cat > "$TMP/sum_literal.ae" <<'AE'
struct Circle { r: int }
struct Square { s: int }
type Shape = Circle | Square
main() {
    let s: Shape = Circle { r: 2 }
    match s {
        5 -> println("five")
        _ -> println("other")
    }
}
AE
expect sum_literal "a match over the sum type 'Shape' takes one variant per arm" \
    "name a variant"

cat > "$TMP/none_on_int.ae" <<'AE'
main() {
    n = 3
    match n {
        none -> println("none")
        _ -> println("other")
    }
}
AE
expect none_on_int "\`none\` matches an optional, and the value matched is an int" \
    "\`none\` and \`some(name)\` arms match a \`T?\` value"

cat > "$TMP/list_on_int.ae" <<'AE'
main() {
    n = 3
    match n {
        [h | t] -> println("list")
        _ -> println("other")
    }
}
AE
expect list_on_int "a list pattern matches an array, a slice or a \`*StringSeq\`" \
    "match the list itself"

cat > "$TMP/range_on_string.ae" <<'AE'
main() {
    s = "abc"
    match s {
        1..=5 -> println("range")
        _ -> println("other")
    }
}
AE
expect range_on_string "a range match arm compares by order, and the value matched is a string" \
    "name the values one by one"

cat > "$TMP/wild_in_list.ae" <<'AE'
main() {
    n = 3
    match n {
        1, _ -> println("one or any")
    }
}
AE
expect wild_in_list "\`_\` takes every value, so it cannot be one of the values a match arm names" \
    "give \`_\` an arm of its own"

cat > "$TMP/case_string.ae" <<'AE'
main() {
    n = 2
    switch n {
        case "two": println("two")
        default: println("other")
    }
}
AE
expect case_string "this case compares the value matched (int) with \"two\", a string" \
    "write a value of type int here"

cat > "$TMP/case_undeclared.ae" <<'AE'
main() {
    n = 2
    switch n {
        case other: println("other")
        default: println("default")
    }
}
AE
expect case_undeclared "'other' names no variable: a case compares the value matched" \
    "write \`default:\` to take every other value"

cat > "$TMP/switch_optional.ae" <<'AE'
main() {
    let m: int? = 5
    switch m {
        case 5: println("five")
        default: println("other")
    }
}
AE
expect switch_optional "a switch compares its value with each case, and an optional cannot" \
    "use \`match\`"

# A variable of the value's type, a constant and an enum member compare as
# before: accepted, and the arm that matches runs.
cat > "$TMP/accepted.ae" <<'AE'
const LIMIT = 3
enum Color { Red, Green }
main() {
    n = 3
    limit = 2
    match n {
        limit -> println("at limit")
        LIMIT -> println("at LIMIT")
        _ -> println("other")
    }
    c = Color.Green
    match c {
        Red -> println("red")
        Color.Green -> println("green")
    }
}
AE
out=$(cd "$TMP" && "$AE" run accepted.ae 2>&1)
if [ "$out" != "at LIMIT
green" ]; then
    echo "  [FAIL] accepted: gave [$out], want at LIMIT then green"
    fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] || exit 1
echo "  [PASS] match_arm_pattern_check: arms and cases are checked against the value matched"
