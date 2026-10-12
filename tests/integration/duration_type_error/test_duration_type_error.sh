#!/bin/sh
# Duration values must not compare against plain numbers silently.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# A directory of its own, not fixed /tmp paths: two sweeps at once (two
# checkouts, or parallel agents) overwrote each other's files (#2770).
AE_TMP="$(mktemp -d)"
trap 'rm -rf "$AE_TMP"' EXIT

cat > $AE_TMP/ae_duration_bad.ae << 'EOF'
main() {
    if 5s > 5 {
        println("bad")
    }
}
EOF

output=$(AETHER_HOME="" "$ROOT/build/ae" build $AE_TMP/ae_duration_bad.ae -o $AE_TMP/ae_duration_bad_out 2>&1)
rm -f $AE_TMP/ae_duration_bad.ae $AE_TMP/ae_duration_bad_out

if echo "$output" | grep -q "Invalid operation for given types"; then
    echo "duration_type_error: PASS"
    exit 0
fi

echo "duration_type_error: FAIL"
echo "$output" | head -20 | sed 's/^/  /'
exit 1
