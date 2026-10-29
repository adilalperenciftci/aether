#!/bin/sh
# `quote` (docs/quote.md): each reject_*.ae must fail to build with its own
# E08xx diagnostic at the line of the construct, and nothing else; a typed
# getter that reads a capture as the wrong type panics naming both types; a
# variable only a quote reads is not reported unused.
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
    "$AE" build "$SCRIPT_DIR/reject_$name.ae" -o "$TMPDIR/out" >"$log" 2>&1
    if [ $? = 0 ]; then
        echo "  [FAIL] quote_errors: reject_$name.ae compiled (should be rejected)"; exit 1
    fi
    # A rejection is a diagnostic and exit 1. `ae build` folds a compiler signal
    # into exit 1 and says so; aetherc itself exits 128+signal.
    if grep -q "killed by signal" "$log"; then
        echo "  [FAIL] quote_errors: reject_$name.ae crashed the compiler"
        sed 's/^/    /' "$log" | head -12; exit 1
    fi
    "$ROOT/build/aetherc" "$SCRIPT_DIR/reject_$name.ae" "$TMPDIR/out.c" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -ge 128 ]; then
        echo "  [FAIL] quote_errors: reject_$name.ae crashed aetherc (exit $rc)"; exit 1
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
reject helper_recursion        E0804 11 "@quotable function 'ping' reaches itself: ping -> pong -> ping"
reject helper_self_recursion   E0804 6  "@quotable function 'fact' reaches itself: fact -> fact"
reject helper_reads_global     E0805 8  "@quotable function 'scale' reads 'gain', a variable outside it"
reject helper_subset           E0800 7  "'defer' can't be in a @quotable function"
reject nested_closure   E0800 8 "a closure or callback can't be quoted"
reject nested_callback  E0800 8 "a closure or callback can't be quoted"
reject nested_block     E0800 8 "a trailing block can't be quoted"
reject interpolation    E0800 8 "string interpolation can't be quoted"
reject array_literal    E0800 8 "an array literal can't be quoted"
reject new              E0800 8 "'new' can't be quoted"
reject match            E0800 8 "'match' can't be quoted"
reject panic            E0800 8 "'panic' can't be quoted"
reject spawn            E0800 9 "'spawn' can't be quoted"
reject send             E0800 10 "an actor send can't be quoted"
reject defer            E0800 8 "'defer' can't be quoted"
reject try              E0800 8 "'try'/'catch' can't be quoted"
reject write_capture    E0803 8 "a quote can't write 'v', a variable it captures"
reject compound_capture E0803 8 "a quote can't write 'v', a variable it captures"
reject step_capture     E0803 8 "a quote can't write 'v', a variable it captures"
reject address_capture  E0803 8 "a quote can't take the address of 'v', a variable it captures"
reject global_write     E0803 8 "a quote can't write 'v', a variable it captures"

if "$AE" run "$SCRIPT_DIR/getter_mismatch.ae" >"$TMPDIR/getter.log" 2>&1; then
    echo "  [FAIL] quote_errors: get_int on a string capture did not panic"; exit 1
fi
if ! grep -q "capture 'name' has type string, not int" "$TMPDIR/getter.log"; then
    echo "  [FAIL] quote_errors: the getter's panic does not name both types"
    sed 's/^/    /' "$TMPDIR/getter.log" | head -8; exit 1
fi

# A variable read only by a quote is used: no W1001 for it.
if ! "$AE" build "$ROOT/tests/regression/test_quote_captures.ae" -o "$TMPDIR/captures" >"$TMPDIR/captures.log" 2>&1; then
    echo "  [FAIL] quote_errors: test_quote_captures.ae did not build"
    sed 's/^/    /' "$TMPDIR/captures.log" | head -8; exit 1
fi
if grep -q "unused variable" "$TMPDIR/captures.log"; then
    echo "  [FAIL] quote_errors: a variable a quote captures is reported unused"
    grep -A2 "unused variable" "$TMPDIR/captures.log" | sed 's/^/    /' | head -8; exit 1
fi

echo "  [PASS] quote_errors: every construct outside the v1 subset, an untyped parameter, the wrong callee, a write to a capture, and a @quotable function that recurses, reads a variable outside it or holds an unquotable construct are rejected; a mistyped getter panics"
exit 0
