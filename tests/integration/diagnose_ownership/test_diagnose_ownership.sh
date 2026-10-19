#!/bin/sh
# Integration: `aetherc --diagnose=ownership` prints how each string store
# is compiled under the ownership model (docs/design/ownership-model.md),
# without running codegen: a store moves a fresh value and takes anything
# else, and every string function hands its caller one reference.
#
# The fixture has a function returning a fresh string (`my_concat`, through
# the dotted `string.concat`) and one returning a parameter or a literal
# (`first_or_default`), and stores of each shape the report classifies.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] diagnose_ownership: aetherc not built"
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/fixture.ae" <<'AE'
import std.string

my_concat(a: string, b: string) -> string {
    return string.concat(a, b)
}

first_or_default(a: string) -> string {
    if string.length(a) > 0 {
        return a
    }
    return "default"
}

main() {
    s = ""
    s = my_concat("hello ", "world")
    s = "literal"
    s = string.concat(s, "!")
}
AE

out="$tmpdir/diagnose.txt"
if ! "$AETHERC" --diagnose=ownership "$tmpdir/fixture.ae" >"$out" 2>&1; then
    echo "  [FAIL] diagnose_ownership: aetherc --diagnose=ownership exited non-zero"
    cat "$out"
    exit 1
fi

# Pass 1: every string function hands its caller one reference.
for fn in my_concat first_or_default; do
    if ! grep -qE "^  $fn .* hands its caller one reference from every return" "$out"; then
        echo "  [FAIL] diagnose_ownership: $fn should hand its caller a reference"
        cat "$out"
        exit 1
    fi
done

# Pass 2: each store, moved or taken.
# `s = ""`                    -> take [literal]
# `s = my_concat(...)`        -> move [fresh: a call's result]
# `s = "literal"`             -> take [literal]
# `s = string.concat(s, "!")` -> move [fresh: a call's result] (the dotted
#                                call is recognised as fresh)
moves=$(grep -cE "^    line +[0-9]+: s +=.*  move +\[fresh" "$out")
takes=$(grep -cE "^    line +[0-9]+: s +=.*  take +\[literal" "$out")
if [ "$moves" != "2" ] || [ "$takes" != "2" ]; then
    echo "  [FAIL] diagnose_ownership: expected 2 moves and 2 takes of s, got $moves and $takes"
    cat "$out"
    exit 1
fi

# The closing note says what move and take mean, and that C borrows unless
# the extern's parameter says `@retain`.
if ! grep -q 'A store marked `move` hands the place' "$out" ||
   ! grep -q 'an extern that keeps it declares the' "$out"; then
    echo "  [FAIL] diagnose_ownership: missing the closing note on move, take and @retain"
    cat "$out"
    exit 1
fi

echo "  [PASS] diagnose_ownership: every string function hands over; stores moved or taken; dotted calls recognised"
exit 0
