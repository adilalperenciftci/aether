#!/bin/sh
# `if c == null` on a closure (#3062) is written `if ((c).fn == 0)`: the
# condition's opener parenthesises it, as for every other `==`. It was
# `if (((c).fn == 0))`, which clang's default -Wparentheses-equality warns
# about at every such `if`, so a program built warning-free failed its
# -Werror build on clang (ae3d's net module). The comparison keeps its own
# parentheses where it is an operand (`&&`, `!`, a value).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

[ -x "$AETHERC" ] || [ -x "$AETHERC.exe" ] || { echo "  [SKIP] closure_null_condition_parens: aetherc not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

cat > "$TMP/main.ae" <<'AE'
struct S { f: fn(@keep ptr, int) -> int }
keeps(p: @keep ptr, i: int) -> int { return i }
main() {
    a = 3
    s = S { f: keeps }
    g = s.f
    if g == null { println("none") }
    if g != null { println("some") }
    while g == null { break }
    if !(g == null) { println("not none") }
    h = g == null
    if a == 3 && g != null { println("both") }
    println("${h}")
}
AE

if ! (cd "$TMP" && AETHER_HOME="$ROOT" "$AETHERC" main.ae main.c >"$TMP/log" 2>&1); then
    echo "  [FAIL] closure_null_condition_parens: aetherc refused the program"
    sed 's/^/        /' "$TMP/log"
    exit 1
fi

# expect <C text>: the generated C holds it, once at least.
expect() {
    if ! grep -qF "$1" "$TMP/main.c"; then
        echo "  [FAIL] closure_null_condition_parens: no \`$1\` in the C"
        grep -n '\.fn [=!]= 0' "$TMP/main.c" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
}
expect 'if ((g).fn == 0) {'
expect 'if ((g).fn != 0) {'
expect 'while ((g).fn == 0) {'
expect '(!((g).fn == 0))'
expect 'h = ((g).fn == 0);'
expect '(a == 3) && ((g).fn != 0)'

if grep -q '(((g)\.fn [=!]= 0))' "$TMP/main.c"; then
    echo "  [FAIL] closure_null_condition_parens: a condition doubly parenthesised"
    grep -n '(((g)\.fn' "$TMP/main.c" | sed 's/^/        /'
    fails=$((fails + 1))
fi

[ $fails -eq 0 ] && echo "  [PASS] closure_null_condition_parens"
[ $fails -eq 0 ]
