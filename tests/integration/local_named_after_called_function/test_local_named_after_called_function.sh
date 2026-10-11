#!/bin/sh
# #2683: `helper = helper() + 1`, a local named after the function its own
# initializer calls, got three different answers: `ae check` of the module on
# its own passed, the same code in a main file passed the checker and failed
# in gcc ("called object 'helper' is not a function"), and an importing
# program failed with E0301 "Undefined function 'helper'", which points away
# from the problem. All three now report the same E0400 at the call; a local
# named apart from the function builds and runs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

fail() { echo "  [FAIL] local_named_after_called_function: $1"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AETHER_CACHE_DIR="$TMP/cache"
cd "$SCRIPT_DIR" || exit 1

expect_e0400() {   # <label> <ae args...>
    label="$1"; shift
    out="$("$AE" "$@" 2>&1)" && { echo "$out"; fail "$label: accepted"; }
    echo "$out" | grep -q "error\[E0400\]: the local 'helper' is named after the function 'helper'" ||
        { echo "$out"; fail "$label: not the E0400 naming the conflict"; }
    echo "$out" | grep -q "E0301\|is not a function" && { echo "$out"; fail "$label: a misleading error too"; }
}

expect_e0400 "the module checked on its own" check lib/shadowlib/module.ae
expect_e0400 "a main file, checked" check mainfile.ae
expect_e0400 "a main file, built" build mainfile.ae -o "$TMP/mainfile"
expect_e0400 "an importing program, checked" check imported.ae

out="$("$AE" run renamed.ae 2>&1)" || { echo "$out"; fail "the renamed local does not build"; }
[ "$out" = "42" ] || { echo "$out"; fail "the renamed local printed the wrong value"; }

echo "  [PASS] local_named_after_called_function: one E0400 wherever the function sits"
