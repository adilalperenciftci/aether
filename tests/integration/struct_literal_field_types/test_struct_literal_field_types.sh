#!/bin/sh
# A struct literal's field values were not checked against the fields'
# types (#2982): `Box { n: "y" }` with `n: int` passed the checker and the C
# compiler refused it ("initialization of 'int' from 'const char *'"). A
# store into the field (`b.n = "y"`) was already refused. Each value now
# fits its field by the rules a store follows: a coercion, a wrap into an
# optional or a sum, `null` or `[]` into a slice, `null` into a string, a
# named function of the signature into a typed function pointer, a byte
# literal in range. The diagnostic names the field and both types.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT" && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] struct_literal_field_types: aetherc not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0

cat > "$tmp/bad.ae" <<'AE'
struct Box {
    n: int
    s: string
    b: byte
    o: int?
}

main() {
    a = Box { n: "y", s: "ok", b: 1, o: 3 }
    c = Box { n: 1, s: 5, b: 300, o: "x" }
    println("${a.n} ${c.n}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/bad.ae" 2>&1)"
for want in \
    "bad.ae:9:[0-9]* .*field 'n' of 'Box' is int: it cannot take a value of type string" \
    "bad.ae:10:[0-9]* .*field 's' of 'Box' is string: it cannot take a value of type int" \
    "bad.ae:10:[0-9]* .*byte literal out of range for field 'b' of 'Box': 300 does not fit in 0..255" \
    "bad.ae:10:[0-9]* .*field 'o' of 'Box' is int?: it cannot take a value of type string"; do
    # Each diagnostic as one line: its message, then its `--> file:line:col`.
    if ! printf '%s\n' "$out" | awk '/^error/ { m = $0; next } /-->/ && m != "" { print $2 " " m; m = "" }' | grep -q "$want"; then
        echo "  [FAIL] struct_literal_field_types: no diagnostic matching: $want"
        fail=1
    fi
done
[ $fail -ne 0 ] && printf '%s\n' "$out" | grep -E "^error|-->" | head -12 | sed 's/^/        |/'

cat > "$tmp/good.ae" <<'AE'
struct All {
    f: float
    l: long
    s: string
    o: int?
    xs: int[]
    cb: fn
    p: ptr
}

twice(x: int) -> int {
    return x * 2
}

main() {
    a = All { f: 1, l: 2, s: null, o: 3, xs: [], cb: twice, p: null }
    b = All { f: 2.5, l: 6000000000, s: "x", o: none, xs: null, cb: |x: int| -> x + 1, p: 0 }
    println("${a.f} ${b.l} ${a.o ?? 0} ${b.o ?? 9} ${call(a.cb, 4)} ${call(b.cb, 4)} ${a.s == null} ${a.xs.len}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AE" run "$tmp/good.ae" 2>&1)"
if [ "$out" != "1 6000000000 3 9 8 5 true 0" ]; then
    echo "  [FAIL] struct_literal_field_types: the fitting values should build and run"
    printf '%s\n' "$out" | head -10 | sed 's/^/        |/'
    fail=1
fi

[ $fail -eq 0 ] && echo "  [PASS] struct_literal_field_types: a struct literal's values are checked against their fields"
exit $fail
