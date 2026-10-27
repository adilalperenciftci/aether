#!/bin/sh
# `@mailbox(bound: N)` (#2974) takes a whole number from 1 and goes before an
# actor; anything else is refused with a message that says what it takes,
# and try_send's target must be an actor reference.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE_TMP="$(mktemp -d)"
trap 'rm -rf "$AE_TMP"' EXIT
fail=0

# $1 = case name, $2 = text the error must hold; the program is on stdin.
refused() {
    cat > "$AE_TMP/$1.ae"
    if out=$(AETHER_HOME="$ROOT" "$ROOT/build/ae" build "$AE_TMP/$1.ae" -o "$AE_TMP/$1" 2>&1); then
        echo "  [FAIL] mailbox_bound_syntax: $1 compiled"
        fail=1
    elif ! echo "$out" | grep -q "$2"; then
        echo "  [FAIL] mailbox_bound_syntax: $1 does not say \"$2\""
        echo "$out" | sed 's/^/    /' | head -8
        fail=1
    fi
}

refused zero "a whole number N from 1" << 'AE'
@mailbox(bound: 0)
actor A { receive { } }
main() { }
AE
refused key "@mailbox takes a bound" << 'AE'
@mailbox(size: 3)
actor A { receive { } }
main() { }
AE
refused not_actor "must precede an .actor. definition" << 'AE'
@mailbox(bound: 3)
struct S { x: int }
main() { }
AE
refused target "is not an actor reference" << 'AE'
message M {}
main() {
    n = 3
    e = try_send(n, M {})
    println(e)
}
AE

[ "$fail" = 0 ] && echo "  [PASS] mailbox_bound_syntax"
exit $fail
