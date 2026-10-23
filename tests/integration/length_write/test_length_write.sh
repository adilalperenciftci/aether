#!/bin/sh
# #3104: `.len` of a slice or an array is a value computed from it (#1286): a
# slice's length is fixed when the slice is made, and an array's is a
# constant. A write to it passed the checker and stopped at the C compiler
# ("lvalue required"), on generated C: `((int)aether_slice_len(xs)) = 2`,
# and `((4) = 3)` for an array. Each way of spelling the write is refused
# here with the checker's own message: `=` as a statement, a compound
# assignment, `++` and `--` in both positions, and `=` on an array. A
# struct's own field named `len` is storage and still takes every one of
# them.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then echo "  [SKIP] length_write: $AE not built"; exit 0; fi
export AETHER_HOME="$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
fail=0

# <name> <pattern the diagnostic must match>; the program is on stdin.
refused() {
    name="$1"; want="$2"
    cat > "$tmp/$name.ae"
    if "$AETHERC" "$tmp/$name.ae" "$tmp/$name.c" >"$tmp/$name.log" 2>&1; then
        echo "  [FAIL] length_write: $name compiled (it must be refused before C)"
        fail=1; return
    fi
    if ! grep -qF "$want" "$tmp/$name.log"; then
        echo "  [FAIL] length_write: $name refused, but not with: $want"
        sed 's/^/        /' "$tmp/$name.log" | head -6
        fail=1
    fi
}

fixed="a slice's length is fixed when the slice is made, and an array's is a constant"

refused assign "cannot write to the length of 'xs': $fixed" <<'AE'
shorten(xs: int[]) -> int {
    xs.len = 2
    return xs[0]
}
main() {
    println("${shorten(make([]int, 4))}")
}
AE
refused compound "cannot write to the length of 'xs': $fixed" <<'AE'
grow(xs: int[]) -> int {
    xs.len += 1
    return 0
}
main() {
    println("${grow(make([]int, 4))}")
}
AE
refused step_post "cannot write to the length of 'xs': $fixed" <<'AE'
step(xs: int[]) -> int {
    xs.len++
    return 0
}
main() {
    println("${step(make([]int, 4))}")
}
AE
refused step_pre "cannot write to the length of 'ys': $fixed" <<'AE'
main() {
    ys = make([]int, 4)
    --ys.len
    println("${ys.len}")
}
AE
refused array "cannot write to the length of 'a': $fixed" <<'AE'
main() {
    int[4] a
    a.len = 3
    println("${a.len}")
}
AE
refused hint "take a slice of the same ones: \`xs[lo..hi]\`" <<'AE'
shorten(xs: int[]) -> int {
    xs.len = 2
    return xs[0]
}
main() {
    println("${shorten(make([]int, 4))}")
}
AE

# A field of a struct's own named `len` is storage like any other.
cat > "$tmp/accepted.ae" <<'AE'
struct Run {
    len: int
}
main() {
    r = Run { len: 1 }
    r.len = 5
    r.len += 2
    r.len++
    --r.len
    xs = make([]int, 4)
    println("${r.len} ${xs.len} ${xs[1..3].len}")
}
AE
if ! "$AE" build "$tmp/accepted.ae" -o "$tmp/accepted" >"$tmp/build.log" 2>&1; then
    echo "  [FAIL] length_write: the accepted forms did not build:"
    grep -m6 -iE "error" "$tmp/build.log" | sed 's/^/        /'
    fail=1
else
    got="$("$tmp/accepted" 2>&1 | tr -d '\r')"
    if [ "$got" != "7 4 2" ]; then
        echo "  [FAIL] length_write: the accepted forms printed '$got', want '7 4 2'"
        fail=1
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] length_write: a write to a slice's or an array's .len is refused before C, by =, a compound assignment, ++ and --; a struct's field named len still takes them"
fi
exit "$fail"
