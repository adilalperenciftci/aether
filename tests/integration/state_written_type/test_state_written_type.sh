#!/bin/sh
# Regression (#3163): a state's value is checked against its written type.
#
# Nothing checked it: `state n: int = "five"` (and the type-first `state int
# n = "five"`) reached C, "makes integer from pointer without a cast". Each is
# now one E0200 at the value, naming the state, its type and the value's, as
# a typed binding's mismatch is. tests/regression/test_state_written_type.ae
# runs the forms that are right.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ] && [ ! -x "$AETHERC.exe" ]; then
    echo "  [SKIP] state_written_type: aetherc not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# refuse NAME DECL WHERE MESSAGE: an actor whose state is DECL is refused with
# one error, E0200 MESSAGE, at WHERE (line:column; the state is on line 4).
refuse() {
    name="$1"; decl="$2"; where="$3"; message="$4"
    printf 'message M {}\n\nactor A {\n    %s\n\n    receive {\n        M -> {\n            println("m")\n        }\n    }\n}\n\nmain() {\n    a = spawn(A())\n    a ! M {}\n    wait_for_idle()\n}\n' "$decl" > "$TMP/$name.ae"
    out="$("$AETHERC" --check "$TMP/$name.ae" 2>&1)"
    errors=$(printf '%s\n' "$out" | grep -c '^error')
    first=$(printf '%s\n' "$out" | grep -m1 '^error')
    at=$(printf '%s\n' "$out" | grep -m1 -- '-->' | sed 's/.*\.ae://')
    if [ "$first" != "error[E0200]: $message" ]; then
        echo "  [FAIL] $name: expected \"error[E0200]: $message\", got: $first"
        fail=1
    elif [ "$errors" -ne 1 ] || [ "$at" != "$where" ]; then
        echo "  [FAIL] $name: $errors error(s), the first at $at (expected 1, at $where)"
        printf '%s\n' "$out" | sed 's/^/        /' | head -12
        fail=1
    else
        echo "  [PASS] $name"
    fi
}

refuse colon_form 'state n: int = "five"' 4:20 \
    "Type mismatch in state initialization: 'n' is int, but this value is string"
refuse type_first 'state int n = "five"' 4:19 \
    "Type mismatch in state initialization: 'n' is int, but this value is string"
refuse optional 'state o: int? = "x"' 4:21 \
    "Type mismatch in state initialization: 'o' is int?, but this value is string"
refuse boolean 'state on: bool = "yes"' 4:22 \
    "Type mismatch in state initialization: 'on' is bool, but this value is string"

exit $fail
