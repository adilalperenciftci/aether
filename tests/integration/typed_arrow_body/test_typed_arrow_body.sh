#!/bin/sh
# Regression (#3158): a written result type before an arrow body is one
# function, checked as one.
#
# `square(x: int) -> int -> x * x` was read as a result type and a block
# body; the missing `{` was "Expected LEFT_BRACE, got ARROW", and the block
# parser went on reading the rest of the file as that block's statements,
# so a later function's `x: int` parameter was "'int' is a reserved keyword".
# Now the form is an arrow body returned against the written type: the
# program from the issue compiles with no error, and an arrow body whose
# value is not of the written type is one E0200, at the value.
# tests/regression/test_typed_arrow_body.ae runs the forms that are right.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ] && [ ! -x "$AETHERC.exe" ]; then
    echo "  [SKIP] typed_arrow_body: aetherc not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

cat > "$TMP/issue.ae" <<'AEOF'
square(x: int) -> int -> x * x

twice(y: int) -> int {
    return y * 2
}

main() {
    println("${square(3)} ${twice(4)}")
}
AEOF
out="$("$AETHERC" --check "$TMP/issue.ae" 2>&1)"
if [ $? -eq 0 ] && ! printf '%s\n' "$out" | grep -q '^error'; then
    echo "  [PASS] issue program compiles"
else
    echo "  [FAIL] issue program: expected no error, got:"
    printf '%s\n' "$out" | sed 's/^/        /' | head -12
    fail=1
fi

cat > "$TMP/mismatch.ae" <<'AEOF'
word(n: int) -> string -> n

later(x: int) -> int {
    return x
}

main() {
    println("${word(1)} ${later(2)}")
}
AEOF
out="$("$AETHERC" --check "$TMP/mismatch.ae" 2>&1)"
errors=$(printf '%s\n' "$out" | grep -c '^error')
first=$(printf '%s\n' "$out" | grep -m1 '^error')
at=$(printf '%s\n' "$out" | grep -m1 -- '-->' | sed 's/.*\.ae://')
case "$first" in
    "error[E0200]: Type mismatch in return: 'word' returns string, but this value is int"*)
        if [ "$errors" -eq 1 ] && [ "$at" = "1:27" ]; then
            echo "  [PASS] a value of another type is one E0200 at the value"
        else
            echo "  [FAIL] mismatch: $errors error(s), first at $at (expected 1, at 1:27)"
            printf '%s\n' "$out" | sed 's/^/        /' | head -12
            fail=1
        fi
        ;;
    *)
        echo "  [FAIL] mismatch: expected E0200 naming the result type, got: $first"
        fail=1
        ;;
esac

exit $fail
