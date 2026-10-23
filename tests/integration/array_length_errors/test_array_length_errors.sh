#!/bin/sh
# Regression (#3115): an array length that is not an integer constant
# expression of at least 1 is a compile error that says what a length may
# be. Before, any length but a decimal number was "Expected NUMBER, got
# IDENTIFIER", and `int[0]` compiled as a slice.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
[ -x "$AETHERC" ] || AETHERC="$ROOT/build/aetherc.exe"

TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
fail=0

# expect <name> <message fragment> <program>
expect() {
    printf '%s\n' "$3" > "$TMPDIR/$1.ae"
    if "$AETHERC" --check "$TMPDIR/$1.ae" > "$TMPDIR/$1.out" 2>&1; then
        echo "  [FAIL] array_length_errors: $1 compiled"
        fail=1
    elif ! grep -qF "$2" "$TMPDIR/$1.out"; then
        echo "  [FAIL] array_length_errors: $1 did not say: $2"
        sed 's/^/    /' "$TMPDIR/$1.out" | head -6
        fail=1
    fi
}

expect unknown_name "array length 'NOPE' is not an integer constant of this file" \
'main() {
    long[NOPE] xs
}'

expect float_const "array length 'F' is not an integer constant of this file" \
'const F = 1.5
main() {
    int[F] xs
}'

expect zero "an array length must be from 1 to" \
'main() {
    int[0] xs
}'

expect negative "an array length must be from 1 to" \
'const N = 2
main() {
    int[N - 5] xs
}'

expect division_by_zero "division by zero in an array length" \
'const N = 0
main() {
    int[4 / N] xs
}'

expect too_large "reaches a value outside that" \
'struct S {
    xs: byte[1 << 40]
}
main() { }'

[ $fail -eq 0 ] && echo "  [PASS] array_length_errors"
exit $fail
