#!/bin/sh
# Regression (#3001): what a diagnostic suggests is Aether.
#
# The @scoped escape error suggested `buf.len()` (tests/integration/
# scoped_escape covers it). The same sweep of the help texts found more:
#   - a call of a function that returns nothing, assigned, said "give it a
#     return type (e.g. `g(...): int`)": a return type is written `-> int`;
#   - an arm with no value in a `match` whose value is used suggested
#     `{ g(...)  0 }`, two statements run together on one line;
#   - a bare ptr given to a slice parameter said "pass its bounded `array()`
#     view": the view is `intarr.array(a)`;
#   - the language server completed math.abs, math.min, math.max, log.info,
#     log.warn, log.error, json.stringify, cryptography.sha256 and the base64
#     calls under std.cryptography, none of which std has.
# Each suggestion below is checked to be there, and the suggested code itself
# is compiled where it is a whole form.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ]; then
    echo "  [SKIP] help_texts_aether: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# expect_help NAME TEXT: `ae check` refuses $TMP/NAME.ae and its output
# contains TEXT.
expect_help() {
    name="$1"; text="$2"
    if "$AE" check "$TMP/$name.ae" >"$TMP/$name.log" 2>&1; then
        echo "  [FAIL] $name: compiled"
        fail=1
        return
    fi
    if grep -qF -- "$text" "$TMP/$name.log"; then
        echo "  [PASS] $name"
    else
        echo "  [FAIL] $name: the diagnostic does not say $text:"
        sed 's/^/        /' "$TMP/$name.log" | head -8
        fail=1
    fi
}

printf 'g() {\n    println("g")\n}\nmain() {\n    x = g()\n    println(x)\n}\n' > "$TMP/void_assign.ae"
expect_help void_assign '`g(...) -> int`'

printf 'g() {\n    println("g")\n}\nmain() {\n    n = 1\n    v = match n {\n        1 -> g()\n        _ -> 0\n    }\n    println(v)\n}\n' > "$TMP/void_arm.ae"
expect_help void_arm '`{ g(...); 0 }`'

# The suggested arm compiles and runs.
printf 'g() {\n    println("g")\n}\nmain() {\n    n = 1\n    v = match n {\n        1 -> { g(); 7 }\n        _ -> 0\n    }\n    println(v)\n}\n' > "$TMP/void_arm_fixed.ae"
out="$("$AE" run "$TMP/void_arm_fixed.ae" 2>&1)"
if [ "$out" = "$(printf 'g\n7')" ]; then
    echo "  [PASS] void_arm_fixed"
else
    echo "  [FAIL] void_arm_fixed: the suggested arm gave: $out"
    fail=1
fi

printf 'sum(xs: int[]) -> int {\n    return xs.len\n}\nmain() {\n    ptr p = null\n    println(sum(p))\n}\n' > "$TMP/ptr_to_slice.ae"
expect_help ptr_to_slice '`intarr.array(a)`'

# Every std call the language server completes is one std exports, under
# its own name or its module's prefixed one.
labels=$(grep -oE '\\"label\\":\\"[a-z_]+\.[a-z_0-9]+\\"' "$ROOT/lsp/aether_lsp.c" |
         sed -E 's/.*:\\"([a-z_]+)\.([a-z_0-9]+)\\"/\1.\2/' | sort -u)
missing=""
for l in $labels; do
    mod=${l%%.*}
    fn=${l#*.}
    f="$ROOT/std/$mod/module.ae"
    if [ ! -f "$f" ]; then missing="$missing $l"; continue; fi
    exports=$(awk '/^exports *\(/{on=1} on{print} on&&/\)/{exit}' "$f" | tr ',()' '   ')
    found=0
    for w in $exports; do
        case "$w" in "$fn"|"${mod}_$fn"|"aether_${mod}_$fn") found=1 ;; esac
    done
    [ $found = 1 ] || missing="$missing $l"
done
if [ -z "$labels" ]; then
    echo "  [FAIL] lsp_completions: no std completions found in lsp/aether_lsp.c"
    fail=1
elif [ -n "$missing" ]; then
    echo "  [FAIL] lsp_completions: completes names std does not export:$missing"
    fail=1
else
    echo "  [PASS] lsp_completions"
fi

exit $fail
