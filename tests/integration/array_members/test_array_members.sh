#!/bin/sh
# #3092: `.len` is an array's one member, a slice's and a fixed-size array's
# alike. `arr.length` passed the checker and stopped at the C compiler
# ("request for member 'length' in something not a structure or union"),
# and so did any other name. Each is refused here with the checker's
# message, which names `.len`; `.len` itself, and a struct's own field
# named `length`, still compile and run.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then echo "  [SKIP] array_members: $AE not built"; exit 0; fi
export AETHER_HOME="$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
fail=0

# <name> <member>; the program is on stdin and must be refused before C.
refused() {
    name="$1"; want="'$2' is not a member of an array: an array's length is \`.len\`, its only member"
    cat > "$tmp/$name.ae"
    if "$AETHERC" "$tmp/$name.ae" "$tmp/$name.c" >"$tmp/$name.log" 2>&1; then
        echo "  [FAIL] array_members: $name compiled (it must be refused before C)"
        fail=1; return
    fi
    if ! grep -qF "$want" "$tmp/$name.log"; then
        echo "  [FAIL] array_members: $name refused, but not with: $want"
        sed 's/^/        /' "$tmp/$name.log" | head -6
        fail=1
    fi
}

refused literal length <<'AE'
main() {
    arr = [1, 2]
    println("${arr.length}")
}
AE
refused slice_param length <<'AE'
count(xs: int[]) -> int {
    return xs.length
}
main() {
    println("${count(make([]int, 3))}")
}
AE
refused fixed size <<'AE'
main() {
    int[4] a
    println("${a.size}")
}
AE
refused closures length <<'AE'
held() {
    println("held")
}
main() {
    fs = [held, null]
    println("${fs.length}")
}
AE

cat > "$tmp/fine.ae" <<'AE'
struct Rope {
    length: int
}
count(xs: int[]) -> int {
    return xs.len
}
main() {
    int[4] a
    r = Rope { length: 7 }
    println("${[1, 2].len} ${count(make([]int, 3))} ${a.len} ${r.length}")
}
AE
out="$(cd "$tmp" && "$AE" run fine.ae 2>&1)"
if [ "$out" != "2 3 4 7" ]; then
    echo "  [FAIL] array_members: .len and a struct field named length, expected '2 3 4 7', got:"
    echo "$out" | sed 's/^/        /' | head -6
    fail=1
fi

[ "$fail" = 0 ] && echo "  [PASS] array_members: every member but .len refused on an array, .len and a struct's length kept"
exit "$fail"
