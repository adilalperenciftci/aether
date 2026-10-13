#!/bin/sh
# `quote` (docs/quote.md): each reject_*.ae must fail to build with its own
# E08xx diagnostic at the line of the construct, and nothing else.
# Pruned from the generic .ae runner (tests/ae_sweep_prune.txt).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
if [ ! -x "$AE" ]; then echo "  [SKIP] quote_errors: $AE not built"; exit 0; fi
TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT

# reject NAME CODE LINE MESSAGE: NAME.ae fails with exactly one error, CODE,
# reported at LINE, whose text holds MESSAGE.
reject() {
    name="$1"; code="$2"; line="$3"; want="$4"
    log="$TMPDIR/$name.log"
    if "$AE" build "$SCRIPT_DIR/reject_$name.ae" -o "$TMPDIR/out" >"$log" 2>&1; then
        echo "  [FAIL] quote_errors: reject_$name.ae compiled (should be rejected)"; exit 1
    fi
    if ! grep -q "error\[$code\]: .*$want" "$log"; then
        echo "  [FAIL] quote_errors: reject_$name.ae: no error[$code] saying \"$want\""
        sed 's/^/    /' "$log" | head -12; exit 1
    fi
    if ! grep -q -- "--> .*reject_$name.ae:$line:" "$log"; then
        echo "  [FAIL] quote_errors: reject_$name.ae: error not reported at line $line"
        sed 's/^/    /' "$log" | head -12; exit 1
    fi
    if [ "$(grep -c 'error\[' "$log")" != 1 ]; then
        echo "  [FAIL] quote_errors: reject_$name.ae: more than the one error"
        sed 's/^/    /' "$log" | head -16; exit 1
    fi
}

reject untyped_param    E0801 8 "quote parameter 'x' has no type"
reject wrong_callee     E0802 8 "'plain' is given a quote, but its last parameter is not a quote.Tree"
reject closure_to_tree  E0802 8 "takes a quote.Tree as its last parameter, but is given a closure"
reject callback_to_tree E0802 8 "takes a quote.Tree as its last parameter, but is given a closure"
reject block_to_tree    E0802 8 "takes a quote.Tree as its last parameter, but is given a block that runs inline"
reject nested_closure   E0800 8 "a closure or callback can't be quoted"
reject nested_callback  E0800 8 "a closure or callback can't be quoted"
reject nested_block     E0800 8 "a trailing block can't be quoted"
reject interpolation    E0800 8 "string interpolation can't be quoted"
reject array_literal    E0800 8 "an array literal can't be quoted"
reject new              E0800 8 "'new' can't be quoted"
reject spawn            E0800 9 "'spawn' can't be quoted"

echo "  [PASS] quote_errors: constructs outside the v1 subset, an untyped parameter and the wrong callee are rejected"
exit 0
