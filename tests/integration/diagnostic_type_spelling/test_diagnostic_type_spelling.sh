#!/bin/sh
# A diagnostic named a type through type_to_string, which spells a closure
# type by its signature and a distinct type by its representation: a `fn?`
# was "|| -> void?", a distinct string's optional `Name?` was "string?", a
# typed function `fn(int) -> int` was "|int| -> int" and a struct "struct
# P". type_to_string stays what the --emit=lib catalog and the schema tables
# read; the diagnostics that used it now spell the type as the source does
# (type_spelled): a destructure of a non-tuple, an optional compared with
# what it cannot hold, a function type whose result is a fixed-size array,
# a slice of another element type, a missing return.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] diagnostic_type_spelling: aetherc not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0

cat > "$tmp/bad.ae" <<'AE'
type Name = distinct string

struct P {
    x: int
}

name_of() -> Name? {
    return none
}

cb_of() -> fn? {
    return none
}

twice(x: int) -> int {
    return x * 2
}

sig_of() -> fn(int) -> int {
    return twice
}

p_of() -> P {
    return P { x: 1 }
}

pairs(g: fn() -> int[2]) {
}

first(names: string[]) -> string {
    return names[0]
}

main() {
    a, b = name_of()
    c, d = cb_of()
    e, f = sig_of()
    h, i = p_of()
    let n: Name? = none
    let g: fn? = none
    println("${n == 3} ${g == 3}")
    let ns: Name[2] = ["a" as Name, "b" as Name]
    println(first(ns))
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/bad.ae" 2>&1)"
for want in \
    "bad.ae:35:[0-9]* .*cannot destructure, 'name_of' returns 'Name?', not a tuple" \
    "bad.ae:36:[0-9]* .*cannot destructure, 'cb_of' returns 'fn?', not a tuple" \
    "bad.ae:37:[0-9]* .*cannot destructure, 'sig_of' returns 'fn(int) -> int', not a tuple" \
    "bad.ae:38:[0-9]* .*cannot destructure, 'p_of' returns 'P', not a tuple" \
    "bad.ae:41:[0-9]* .*'==' compares the optional 'Name?' with 'int'" \
    "bad.ae:41:[0-9]* .*'==' compares the optional 'fn?' with 'int'" \
    "bad.ae:27:[0-9]* .*parameter 'g' holds the function type fn() -> int\[2\], which returns int\[2\]" \
    "bad.ae:43:[0-9]* .*cannot view Name elements as string\[\]"; do
    # Each diagnostic as one line: its message, then its `--> file:line:col`.
    if ! printf '%s\n' "$out" | awk '/^error/ { m = $0; next } /-->/ && m != "" { print $2 " " m; m = "" }' | grep -q "$want"; then
        echo "  [FAIL] diagnostic_type_spelling: no diagnostic matching: $want"
        fail=1
    fi
done
if printf '%s' "$out" | grep -q -e '|| -> void' -e 'string?' -e '|int|' -e "'struct P'"; then
    echo "  [FAIL] diagnostic_type_spelling: a type is still spelled by its representation"
    fail=1
fi
[ $fail -ne 0 ] && printf '%s\n' "$out" | grep -E "^error|-->" | head -30 | sed 's/^/        |/'

# A missing return names the result type as written.
cat > "$tmp/noreturn.ae" <<'AE'
type Name = distinct string

label(n: int) -> Name? {
    if n > 0 {
        return none
    }
}

main() {
    println("${label(1) == none}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/noreturn.ae" 2>&1)"
if ! printf '%s' "$out" | grep -q "missing return: control can reach the end of 'label', whose result is Name?"; then
    echo "  [FAIL] diagnostic_type_spelling: the missing return does not name Name?"
    printf '%s\n' "$out" | head -8 | sed 's/^/        |/'
    fail=1
fi

[ $fail -eq 0 ] && echo "  [PASS] diagnostic_type_spelling: diagnostics spell fn?, a distinct optional, a typed function and a struct as the source does"
exit $fail
