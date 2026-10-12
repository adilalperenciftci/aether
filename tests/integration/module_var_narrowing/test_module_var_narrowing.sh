#!/bin/sh
# Issue #929: the #698 silent-narrowing guard (E0200) was not applied
# to a MODULE-SCOPE `var x = 0`. The width was inferred as 32-bit int
# from the bare initializer, but a later 64-bit assignment to the
# global truncated silently — unlike the identical local-variable path,
# which already errored. The fix marks the global's inferred type so
# the guard fires.
#
# Three cases:
#   1. inferred-int global + 64-bit assignment  -> MUST error E0200
#   2. explicit `var x: long` global            -> MUST compile (exempt)
#   3. plain int global + int assignment        -> MUST compile (no false +)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# A directory of its own, not fixed /tmp paths: two sweeps at once (two
# checkouts, or parallel agents) overwrote each other's files (#2770).
AE_TMP="$(mktemp -d)"
trap 'rm -rf "$AE_TMP"' EXIT
AE="$ROOT/build/ae"

# --- Case 1: must be rejected with E0200 -----------------------------
cat > $AE_TMP/ae_modvar_bad.ae << 'EOF'
import std.os
var cell = 0
main() {
    cell = os.now_monotonic_ns()
    println("${cell}")
}
EOF
out1=$(AETHER_HOME="" "$AE" build $AE_TMP/ae_modvar_bad.ae -o $AE_TMP/ae_modvar_bad_out 2>&1)
rm -f $AE_TMP/ae_modvar_bad.ae $AE_TMP/ae_modvar_bad_out
if ! echo "$out1" | grep -q "E0200"; then
    echo "module_var_narrowing: FAIL (inferred-int global was NOT guarded)"
    echo "$out1" | head -20 | sed 's/^/  /'
    exit 1
fi

# --- Case 2: explicit long global must compile -----------------------
cat > $AE_TMP/ae_modvar_long.ae << 'EOF'
import std.os
var cell: long = 0
main() {
    cell = os.now_monotonic_ns()
    println("${cell}")
}
EOF
out2=$(AETHER_HOME="" "$AE" build $AE_TMP/ae_modvar_long.ae -o $AE_TMP/ae_modvar_long_out 2>&1)
rc2=$?
rm -f $AE_TMP/ae_modvar_long.ae $AE_TMP/ae_modvar_long_out
if [ "$rc2" -ne 0 ]; then
    echo "module_var_narrowing: FAIL (explicit-long global was wrongly rejected)"
    echo "$out2" | head -20 | sed 's/^/  /'
    exit 1
fi

# --- Case 3: plain int global, int assignment must compile -----------
cat > $AE_TMP/ae_modvar_int.ae << 'EOF'
var counter = 0
main() {
    counter = counter + 1
    counter = 42
    println("${counter}")
}
EOF
out3=$(AETHER_HOME="" "$AE" build $AE_TMP/ae_modvar_int.ae -o $AE_TMP/ae_modvar_int_out 2>&1)
rc3=$?
rm -f $AE_TMP/ae_modvar_int.ae $AE_TMP/ae_modvar_int_out
if [ "$rc3" -ne 0 ]; then
    echo "module_var_narrowing: FAIL (plain int global was wrongly rejected)"
    echo "$out3" | head -20 | sed 's/^/  /'
    exit 1
fi

echo "module_var_narrowing: PASS"
exit 0
