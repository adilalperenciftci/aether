#!/bin/sh
# A pointer moves by an integer of any width, in both directions (#3045):
# `p - n` with a `long` n was E0200 "Type mismatch in variable
# initialization", as were `p + n` and `n + p` with a long bound to a local,
# while an `int` n passed. And a number less a pointer, `n - p`, which C
# refuses ("invalid operands to binary -"), reached the C compiler; it is
# the checker's error now. What the offsets compute is
# tests/regression/test_issue3045_ptr_integer_offsets.ae.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] ptr_offset_arithmetic: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

cat > "$TMP/offsets.ae" <<'AE'
offsets(p: @into ptr, n: long, w: uint32, b: byte) -> ptr {
    s = p - n
    t = p + n
    u = n + p
    v = p - w
    x = b + p
    if s == t || u == v { return x }
    return p - b
}

main() {
    long n = 1
    println("${offsets(null, n, 2, 3) == null}")
}
AE
out=$(cd "$TMP" && "$AE" check offsets.ae 2>&1)
if [ $? -ne 0 ]; then
    echo "  [FAIL] offsets: refused"; echo "$out" | sed 's/^/        /'; fails=$((fails + 1))
fi

cat > "$TMP/number_less_pointer.ae" <<'AE'
back(p: ptr) -> long {
    q = 10 - p
    return 0
}

main() { println("${back(null)}") }
AE
out=$(cd "$TMP" && "$AE" check number_less_pointer.ae 2>&1)
case "$out" in
    *"error[E0200]: a pointer cannot be subtracted from a number"*"number_less_pointer.ae:2:12"*) ;;
    *) echo "  [FAIL] number_less_pointer: not refused at 2:12"; echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

# #3048: a bare `ptr` has no fields. A field read or stored through one,
# moved or not, passed the checker untyped and reached C as a member of a `void*`
# ("request for member in something not a structure or union"). A typed
# pointer moved by an integer keeps its type and its fields
# (tests/regression/test_issue3048_typed_ptr_offset.ae).
cat > "$TMP/bare_ptr_field.ae" <<'AE'
struct Node { v: int, w: int }

second_w(p: ptr) -> int {
    return (p + 8).w
}

first_v(p: ptr) -> int {
    return p.v
}

set_w(p: ptr) {
    p.w = 1
}

main() {
    set_w(null)
    println("${second_w(null) + first_v(null)}")
}
AE
out=$(cd "$TMP" && "$AE" check bare_ptr_field.ae 2>&1)
case "$out" in
    *"Type 'ptr' has no field 'w'"*"bare_ptr_field.ae:4:"*"Type 'ptr' has no field 'v'"*"bare_ptr_field.ae:8:"*"Type 'ptr' has no field 'w'"*"bare_ptr_field.ae:12:"*) ;;
    *) echo "  [FAIL] bare_ptr_field: not refused at 4, 8 and 12"; echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] ptr_offset_arithmetic: a pointer moves by an int, long, uint32 or byte both ways; n - p and a field of a bare ptr are refused"
