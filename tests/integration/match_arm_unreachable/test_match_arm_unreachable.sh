#!/bin/sh
# Regression (#1377): match arms are tried in source order, so an arm that can
# never be reached is dead code. Until now a duplicated arm, or one below a `_`
# catch-all, compiled clean and silently never ran.
#
# These are warnings, not errors: the programs still compile. So the test
# asserts the diagnostic text AND, just as importantly, that the valid shapes
# stay completely silent. A warning that fires on correct code is worse than no
# warning at all, which is why a bare-identifier arm naming a variable (whose
# value is not known when the program is compiled) is deliberately never
# compared.
#
# #2728: over an enum, a sum or an optional the cases are closed, so a second
# arm for the same member (qualified, bare, or one of each), variant or `none`
# is reported too, and so is a comma-list every value of which is already
# handled. The string literal "_" is a string, not the wildcard.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] match_arm_unreachable: aetherc not built"
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
fail=0

# $1 = fixture basename, $2 = extended regex the warning must match
expect_warning() {
    name="$1"
    want="$2"
    "$AETHERC" "$SCRIPT_DIR/$name.ae" "$TMPDIR/$name.c" >"$TMPDIR/$name.log" 2>&1
    if ! grep -qE "$want" "$TMPDIR/$name.log"; then
        echo "  [FAIL] match_arm_unreachable: $name.ae did not warn as expected"
        echo "         expected a diagnostic matching: $want"
        sed 's/^/    /' "$TMPDIR/$name.log" | head -8
        fail=1
    fi
}

expect_no_warning() {
    name="$1"
    "$AETHERC" "$SCRIPT_DIR/$name.ae" "$TMPDIR/$name.c" >"$TMPDIR/$name.log" 2>&1
    if grep -qi "W1004" "$TMPDIR/$name.log"; then
        echo "  [FAIL] match_arm_unreachable: $name.ae warned, but it is valid code"
        sed 's/^/    /' "$TMPDIR/$name.log" | head -8
        fail=1
    fi
}

expect_warning warn_duplicate_arm      'W1004.*already handled on line 10'
expect_warning warn_redundant_catchall 'W1004.*every member of enum .Direction. is already handled'
expect_warning warn_arm_after_wildcard 'W1004.*`_` arm on line 9'
expect_warning warn_duplicate_enum_member  'W1004.*already handled on line 11'
expect_warning warn_duplicate_bare_member  'W1004.*already handled on line 9'
expect_warning warn_duplicate_mixed_member 'W1004.*already handled on line 9'
expect_warning warn_duplicate_variant      'W1004.*already handled on line 12'
expect_warning warn_duplicate_none         'W1004.*already handled on line 8'
expect_warning warn_covered_comma_list     'W1004.*already handled on line 7'
expect_no_warning ok_distinct_arms
expect_no_warning ok_variable_arm
expect_no_warning ok_partial_catchall
expect_no_warning ok_long_arms
expect_no_warning ok_partial_comma_list
expect_no_warning ok_underscore_string

# These compile: the duplicate variant arm made a second C `case` for the
# same value, which the C compiler refused, and the string "_" was taken for
# the wildcard (C: "else without a previous if").
AE="$ROOT/build/ae"
for name in warn_duplicate_variant ok_underscore_string; do
    if [ -x "$AE" ] && ! (cd "$TMPDIR" && cp "$SCRIPT_DIR/$name.ae" . &&
                          "$AE" build "$name.ae" -o "$TMPDIR/$name.bin" >"$TMPDIR/$name.build.log" 2>&1); then
        echo "  [FAIL] match_arm_unreachable: $name.ae did not build"
        sed 's/^/    /' "$TMPDIR/$name.build.log" | head -8
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] match_arm_unreachable: duplicate, covered and post-wildcard arms warn; valid shapes silent"
fi
exit $fail
