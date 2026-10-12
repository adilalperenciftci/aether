#!/bin/sh
# Issue #480: distinct types are nominally separate from their base. Each
# reject_*.ae crosses the distinct boundary WITHOUT an `as` cast and MUST fail
# to build. The allowed (cast) shapes are covered by the regression test
# test_issue480_distinct.ae. Pruned from the generic .ae runner.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
if [ ! -x "$AE" ]; then echo "  [SKIP] distinct_types: $AE not built"; exit 0; fi
TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
check_rejected() {
    name="$1"
    if "$AE" build "$SCRIPT_DIR/$name.ae" -o "$TMPDIR/out" >"$TMPDIR/$name.log" 2>&1; then
        echo "  [FAIL] distinct_types: $name.ae compiled (should be rejected)"; exit 1
    fi
    if ! grep -qiE 'distinct|mismatch|expected .* got' "$TMPDIR/$name.log"; then
        echo "  [FAIL] distinct_types: $name.ae failed without a type diagnostic"
        sed 's/^/    /' "$TMPDIR/$name.log" | head -8; exit 1
    fi
}
check_rejected reject_raw_assign
check_rejected reject_cross_call
# The diagnostic names both distinct types; reported by their base, it read
# "expected float, got float".
if ! grep -q 'expected USD, got EUR' "$TMPDIR/reject_cross_call.log"; then
    echo "  [FAIL] distinct_types: the cross-call diagnostic does not name USD and EUR"
    sed 's/^/    /' "$TMPDIR/reject_cross_call.log" | head -8; exit 1
fi
check_rejected reject_unwrap
# An operator does not mix two distinct types either, arithmetic, comparison
# or compound assignment, over a scalar base or a lane base. Each is named by
# the distinct types themselves, and reported once (no cascade into "If
# condition must be boolean" or "cannot cast unknown").
check_rejected reject_mixed_operator
for want in "'+' mixes distinct types USD and EUR" \
            "'<' mixes distinct types USD and EUR" \
            "'+=' mixes distinct types USD and EUR"; do
    if ! grep -q "$want" "$TMPDIR/reject_mixed_operator.log"; then
        echo "  [FAIL] distinct_types: no \"$want\" diagnostic"
        sed 's/^/    /' "$TMPDIR/reject_mixed_operator.log" | head -12; exit 1
    fi
done
if ! grep -q 'Type checking failed with 3 error' "$TMPDIR/reject_mixed_operator.log"; then
    echo "  [FAIL] distinct_types: a mixed-distinct operator cascaded into further errors"
    sed 's/^/    /' "$TMPDIR/reject_mixed_operator.log" | head -12; exit 1
fi
check_rejected reject_mixed_lane_operator
if ! grep -q "'+' mixes distinct types vec3 and vec4" "$TMPDIR/reject_mixed_lane_operator.log"; then
    echo "  [FAIL] distinct_types: vec3 + vec4 (both distinct f32x4) not reported by name"
    sed 's/^/    /' "$TMPDIR/reject_mixed_lane_operator.log" | head -8; exit 1
fi
echo "  [PASS] distinct_types: raw-assign / cross-distinct-call / unwrap-without-cast / mixed-distinct operators all rejected"
exit 0
