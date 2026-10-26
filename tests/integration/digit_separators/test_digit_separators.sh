#!/bin/sh
# Regression (#3155): a misplaced `_` in a number literal is one error, at
# the `_`, naming it.
#
# An underscore separates two digits of one run, in every base: the integer
# digits, the fraction, the exponent and a duration's digits. The prefixed
# bases used to skip every `_` wherever it stood (`0xFF_`, `0b1__0` and
# `0x_FF` compiled), and a decimal literal stopped at the first one, so
# `1_` was the number 1 and then a name. Each misplaced form below must be
# refused with exactly one error, E0100 "misplaced `_` in a number", at the
# `_` it names. tests/regression/test_digit_separators.ae runs the forms
# that are right.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ] && [ ! -x "$AETHERC.exe" ]; then
    echo "  [SKIP] digit_separators: aetherc not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# refuse NAME LITERAL COLUMN: `x = LITERAL` on line 2 is refused with one
# error, E0100 "misplaced `_` in a number", at 2:COLUMN.
refuse() {
    name="$1"; literal="$2"; column="$3"
    printf 'main() {\n    x = %s\n    println("${x}")\n}\n' "$literal" > "$TMP/$name.ae"
    out="$("$AETHERC" --check "$TMP/$name.ae" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  [FAIL] $name ($literal): compiled"
        fail=1
        return
    fi
    errors=$(printf '%s\n' "$out" | grep -c '^error')
    first=$(printf '%s\n' "$out" | grep -m1 '^error')
    at=$(printf '%s\n' "$out" | grep -m1 -- '-->' | sed 's/.*\.ae://')
    if [ "$first" != 'error[E0100]: misplaced `_` in a number' ]; then
        echo "  [FAIL] $name ($literal): expected the misplaced \`_\` error, got: $first"
        fail=1
        return
    fi
    if [ "$at" != "2:$column" ]; then
        echo "  [FAIL] $name ($literal): reported at $at, expected 2:$column"
        fail=1
        return
    fi
    if [ "$errors" -ne 1 ]; then
        echo "  [FAIL] $name ($literal): expected 1 error, got $errors"
        fail=1
        return
    fi
    echo "  [PASS] $name"
}

refuse trailing        '1_'      10
refuse doubled         '1__000'  10
refuse before_point    '1_.5'    10
refuse after_point     '1._5'    11
refuse before_exponent '1_e5'    10
refuse after_exponent  '1e_5'    11
refuse exponent_end    '1e5_'    12
refuse duration_unit   '5_ms'    10
refuse after_prefix    '0x_FF'   11
refuse hex_trailing    '0xFF_'   13
refuse octal_doubled   '0o7__5'  12
refuse binary_doubled  '0b1__0'  12

# The help line says where an underscore goes.
printf 'main() {\n    x = 1_\n}\n' > "$TMP/help.ae"
if "$AETHERC" --check "$TMP/help.ae" 2>&1 | grep -q 'help: an underscore goes between two digits'; then
    echo "  [PASS] help"
else
    echo "  [FAIL] help: no help line naming where an underscore goes"
    fail=1
fi

exit $fail
