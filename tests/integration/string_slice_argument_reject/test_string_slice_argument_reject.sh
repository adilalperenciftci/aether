#!/bin/sh
# A string passed where a parameter takes a slice (`byte[]`, any `T[]`) was
# let through by the checker, though a binding (`byte[] v = "abc"`) and a
# `return` refused it. An Aether function's `T[]` parameter then got a
# `const char*` where C wants an AetherSlice, and the generated C did not
# compile (`cryptography.sha256_hex("abc")` among them). An extern's got the
# counted string's header instead of its bytes. A string is not a slice
# (language reference, Slices: the conversions are a `T[N]` array, `null`
# and `[]`). It is now refused at the call, a literal and a string local
# alike, and a `byte[]` slot's diagnostic names `string.bytes(s)`. That
# form compiles and runs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT" && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] string_slice_argument_reject: aetherc not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0

cat > "$tmp/bad.ae" <<'AE'
import std.cryptography

count(data: byte[]) -> int { return data.len }
ints(xs: int[]) -> int { return xs.len }
extern memchr(p: byte[], c: int, n: long) -> ptr

main() {
    s = "hello"
    println("${count("abc")}")
    println("${count(s)}")
    println("${ints("abc")}")
    q = memchr(s, 104, 5)
    h, _e = cryptography.sha256_hex("abc")
    println("${q != null} ${h}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" "$tmp/bad.ae" "$tmp/bad.c" 2>&1)"
for want in \
    "bad.ae:9:[0-9]* .*Argument 1 'data' of 'count': expected byte\[\], got string" \
    "bad.ae:10:[0-9]* .*Argument 1 'data' of 'count': expected byte\[\], got string" \
    "bad.ae:11:[0-9]* .*Argument 1 'xs' of 'ints': expected int\[\], got string; a string is not a slice" \
    "bad.ae:12:[0-9]* .*Argument 1 'p' of 'memchr': expected byte\[\], got string" \
    "bad.ae:13:[0-9]* .*Argument 1 'data' of 'cryptography.sha256_hex': expected byte\[\], got string"; do
    # Each diagnostic as one line: its message, then its `--> file:line:col`.
    if ! printf '%s\n' "$out" | awk '/^error\[/ { m = $0; next } /-->/ && m != "" { print $2 " " m; m = "" }' | grep -q "$want"; then
        echo "  [FAIL] string_slice_argument_reject: no diagnostic matching: $want"
        fail=1
    fi
done
if ! printf '%s' "$out" | grep -q 'pass `string.bytes(s)`'; then
    echo "  [FAIL] string_slice_argument_reject: a byte[] slot's diagnostic does not name string.bytes(s)"
    fail=1
fi
[ $fail -ne 0 ] && printf '%s\n' "$out" | head -20 | sed 's/^/        |/'

cat > "$tmp/good.ae" <<'AE'
import std.cryptography
import std.string

count(data: byte[]) -> int { return data.len }
extern memchr(p: byte[], c: int, n: long) -> ptr

main() {
    s = "hello"
    q = memchr(string.bytes(s), 108, 5)
    h, _e = cryptography.sha256_hex(string.bytes("abc"))
    println("${count(string.bytes("abc"))} ${count(string.bytes(s))} ${q != null} ${h}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AE" run "$tmp/good.ae" 2>&1)"
if [ "$out" != "3 5 true ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]; then
    echo "  [FAIL] string_slice_argument_reject: the string.bytes(s) form should build and run"
    printf '%s\n' "$out" | head -8 | sed 's/^/        |/'
    fail=1
fi

[ $fail -eq 0 ] && echo "  [PASS] string_slice_argument_reject: a string passed to a slice parameter is refused at the call; string.bytes(s) works"
exit $fail
