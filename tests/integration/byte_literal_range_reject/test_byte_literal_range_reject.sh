#!/bin/sh
# Tests that out-of-range integer literals assigned to a `byte` slot
# are rejected at typecheck time with a helpful diagnostic. Per Nic's
# pick of option (b): catch obvious typos at compile time; allow non-
# literal int assignment with runtime truncation (matching how other
# narrowings behave).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# A directory of its own, not fixed /tmp paths: two sweeps at once (two
# checkouts, or parallel agents) overwrote each other's files (#2770).
AE_TMP="$(mktemp -d)"
trap 'rm -rf "$AE_TMP"' EXIT

pass=0
fail=0

# Case 1: literal too high (256).
cat > $AE_TMP/ae_byte_bad1.ae << 'EOF'
main() {
    byte b = 256
    println(b)
}
EOF
output=$(AETHER_HOME="" "$ROOT/build/ae" build $AE_TMP/ae_byte_bad1.ae -o $AE_TMP/ae_byte_bad1_out 2>&1)
if echo "$output" | grep -q "byte literal out of range"; then
    echo "  [PASS] literal 256 rejected"
    pass=$((pass + 1))
else
    echo "  [FAIL] expected 'byte literal out of range' diagnostic; got:"
    echo "$output" | head -10 | sed 's/^/    /'
    fail=$((fail + 1))
fi

# Case 2: negative literal.
cat > $AE_TMP/ae_byte_bad2.ae << 'EOF'
main() {
    byte b = 0 - 1
    println(b)
}
EOF
# Note: this case actually uses `0 - 1` as an expression (not a literal),
# so it should NOT be caught by the literal-range check — the typechecker
# only catches actual literals. This case is a sentry: confirm the check
# doesn't over-fire on expressions.
if AETHER_HOME="" "$ROOT/build/ae" build $AE_TMP/ae_byte_bad2.ae -o $AE_TMP/ae_byte_bad2_out 2>/dev/null; then
    echo "  [PASS] '0 - 1' (expression, not literal) compiles — runtime truncate path"
    pass=$((pass + 1))
else
    echo "  [FAIL] expression-form '0 - 1' should compile (range check is literal-only)"
    fail=$((fail + 1))
fi

# Case 3: hex literal too high (0x100 = 256).
cat > $AE_TMP/ae_byte_bad3.ae << 'EOF'
main() {
    byte b = 0x100
    println(b)
}
EOF
output=$(AETHER_HOME="" "$ROOT/build/ae" build $AE_TMP/ae_byte_bad3.ae -o $AE_TMP/ae_byte_bad3_out 2>&1)
if echo "$output" | grep -q "byte literal out of range"; then
    echo "  [PASS] hex literal 0x100 rejected"
    pass=$((pass + 1))
else
    echo "  [FAIL] expected diagnostic for 0x100"
    echo "$output" | head -10 | sed 's/^/    /'
    fail=$((fail + 1))
fi

# Case 4: assignment after declaration also gets the check.
cat > $AE_TMP/ae_byte_bad4.ae << 'EOF'
main() {
    byte b = 0
    b = 999
    println(b)
}
EOF
output=$(AETHER_HOME="" "$ROOT/build/ae" build $AE_TMP/ae_byte_bad4.ae -o $AE_TMP/ae_byte_bad4_out 2>&1)
if echo "$output" | grep -q "byte literal out of range"; then
    echo "  [PASS] reassignment to 999 rejected"
    pass=$((pass + 1))
else
    echo "  [FAIL] expected diagnostic for reassignment to 999"
    echo "$output" | head -10 | sed 's/^/    /'
    fail=$((fail + 1))
fi

# Case 5: in-range literal still compiles.
cat > $AE_TMP/ae_byte_ok.ae << 'EOF'
main() {
    byte b = 255
    println(b)
}
EOF
if AETHER_HOME="" "$ROOT/build/ae" build $AE_TMP/ae_byte_ok.ae -o $AE_TMP/ae_byte_ok_out 2>/dev/null; then
    if $AE_TMP/ae_byte_ok_out 2>&1 | grep -q "^255$"; then
        echo "  [PASS] in-range literal (255) compiles + runs"
        pass=$((pass + 1))
    else
        echo "  [FAIL] 255 compiled but produced wrong value"
        fail=$((fail + 1))
    fi
else
    echo "  [FAIL] 255 should compile (in range)"
    fail=$((fail + 1))
fi

rm -f $AE_TMP/ae_byte_bad*.ae $AE_TMP/ae_byte_bad*_out \
      $AE_TMP/ae_byte_ok.ae $AE_TMP/ae_byte_ok_out

echo ""
echo "byte_literal_range_reject: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
