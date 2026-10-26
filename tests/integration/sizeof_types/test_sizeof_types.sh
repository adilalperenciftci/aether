#!/bin/sh
# Regression (#3174): sizeof and offsetof read their type with the type
# parser, so they take the types a declaration takes, and say so when given
# something else.
#
# The operand was read as one identifier: `sizeof(int)` was "'int' is a
# reserved keyword and cannot be used as an identifier", `sizeof(gpu.Shader)`
# stopped at the dot, and a width name like `uint32` became
# `sizeof(struct uint32)` in the C. tests/regression/test_sizeof_types.ae
# runs the types of one file. Here: a struct from another module, measured
# by its qualified name; `offsetof` over a type that is not a struct, one
# error at the type; and a `sizeof` with no type, one error at what stands
# there instead.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] sizeof_types: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

mkdir -p "$TMP/lib/shapes"
cat > "$TMP/lib/shapes/module.ae" <<'AEOF'
exports(Rect)

struct Rect {
    w: int
    h: long
}
AEOF
cat > "$TMP/main.ae" <<'AEOF'
import shapes

const RECT_BYTES = sizeof(shapes.Rect)

main() {
    println("${RECT_BYTES} ${offsetof(shapes.Rect, h)} ${sizeof(*shapes.Rect) == sizeof(ptr)}")
}
AEOF
got="$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run main.ae 2>&1)"
if [ "$got" = "16 8 true" ]; then
    echo "  [PASS] a qualified struct is measured by sizeof and offsetof"
else
    echo "  [FAIL] qualified struct: expected \"16 8 true\", got:"
    printf '%s\n' "$got" | sed 's/^/        /' | head -12
    fail=1
fi

# check FILE LABEL MESSAGE AT: exactly one error, MESSAGE, at line:column AT.
check() {
    out="$("$AETHERC" --check "$1" 2>&1)"
    errors=$(printf '%s\n' "$out" | grep -c '^error')
    first=$(printf '%s\n' "$out" | grep -m1 '^error')
    at=$(printf '%s\n' "$out" | grep -m1 -- '-->' | sed 's/.*\.ae://')
    case "$first" in
        *"$3"*)
            if [ "$errors" -eq 1 ] && [ "$at" = "$4" ]; then
                echo "  [PASS] $2"
            else
                echo "  [FAIL] $2: $errors error(s), first at $at (expected 1, at $4)"
                printf '%s\n' "$out" | sed 's/^/        /' | head -12
                fail=1
            fi
            ;;
        *)
            echo "  [FAIL] $2: expected \"$3\", got: $first"
            printf '%s\n' "$out" | sed 's/^/        /' | head -12
            fail=1
            ;;
    esac
}

cat > "$TMP/not_struct.ae" <<'AEOF'
main() {
    println("${offsetof(int, x)}")
}
AEOF
check "$TMP/not_struct.ae" "offsetof over int is one error at the type" \
    "offsetof takes a struct type: only a struct has fields to measure" "2:25"

cat > "$TMP/no_type.ae" <<'AEOF'
main() {
    println("${sizeof(3)}")
}
AEOF
check "$TMP/no_type.ae" "sizeof of a number is one error at the number" \
    "sizeof expects a type" "2:23"

exit $fail
