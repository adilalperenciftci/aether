#!/bin/sh
# #2787: `ae fmt` keeps the space between a keyword and the array literal
# after it.
#
# The formatter wrote no space before a `[` that followed any word token,
# taking it for an index, and a keyword is a word token: `return []` came out
# as `return[]` and `for x in [4, 5]` as `in[4, 5]`. Only a value is indexed
# (`xs[0]`, `a[1]`), and `fn[2]` sizes an array type; after any other keyword
# the `[` opens a literal.
#
# The input and the expected output are here rather than as .ae files, so
# the fmt gate and the .ae sweep do not pick them up.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] fmt_bracket_after_keyword: ae not built"
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/in.ae" <<'EOF'
struct H {
    cbs: fn[2]
}
none_of() -> int[] {
    return[]
}
pair() -> (int[], string) {
    return[1, 2], "two"
}
main() {
    xs = [1, 2, 3]
    y = xs [0]
    for x in[4, 5] {
        println("${x} ${y}")
    }
    a, b = pair()
    z = a [1]
    println("${none_of().len} ${z} ${b}")
}
EOF

cat >"$TMPDIR/want.ae" <<'EOF'
struct H {
    cbs: fn[2]
}
none_of() -> int[] {
    return []
}
pair() -> (int[], string) {
    return [1, 2], "two"
}
main() {
    xs = [1, 2, 3]
    y = xs[0]
    for x in [4, 5] {
        println("${x} ${y}")
    }
    a, b = pair()
    z = a[1]
    println("${none_of().len} ${z} ${b}")
}
EOF

cp "$TMPDIR/in.ae" "$TMPDIR/fmt.ae"
if ! "$AE" fmt "$TMPDIR/fmt.ae" >"$TMPDIR/fmt.log" 2>&1; then
    echo "  [FAIL] fmt_bracket_after_keyword: ae fmt failed"
    sed 's/^/    /' "$TMPDIR/fmt.log"
    exit 1
fi
got="$(tr -d '\r' <"$TMPDIR/fmt.ae")"
want="$(cat "$TMPDIR/want.ae")"
if [ "$got" != "$want" ]; then
    echo "  [FAIL] fmt_bracket_after_keyword: formatted output differs; got:"
    printf '%s\n' "$got" | sed 's/^/    /'
    exit 1
fi
if ! "$AE" fmt --check "$TMPDIR/want.ae" >"$TMPDIR/check.log" 2>&1; then
    echo "  [FAIL] fmt_bracket_after_keyword: the canonical form is not stable:"
    sed 's/^/    /' "$TMPDIR/check.log"
    exit 1
fi
echo "  [PASS] fmt_bracket_after_keyword: a literal after a keyword keeps its space"
exit 0
