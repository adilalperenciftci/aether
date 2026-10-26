#!/bin/sh
# Two different enums never convert, `as` included (#3157): the cast check
# let `Color.Red as Direction` through because both are enums, one kind.
# A cast to or from an integer is accepted; see
# tests/regression/test_enum_as_int.ae.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -x "$AE" ] || AE="$ROOT/build/ae.exe"
[ -x "$AE" ] || { echo "  [SKIP] enum_cast_reject: ae not built"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT

cat > "$tmp/two.ae" <<'AE'
enum Color { Red, Green }
enum Direction { North, East }

main() {
    d = Color.Green as Direction
    println("${d == Direction.East}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AE" check "$tmp/two.ae" 2>&1)"
if ! printf '%s' "$out" | grep -qF "cannot cast Color to Direction with \`as\`: two different enums never convert"; then
    echo "  [FAIL] enum_cast_reject: a cast between two enums was not refused"
    printf '%s\n' "$out" | grep -E "^error" | head -3 | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] enum_cast_reject"
