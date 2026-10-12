#!/bin/sh
# #2677: a bare Aether function passed to an extern's typed fn-pointer
# parameter (`fn(int)`) lowers to the plain C function pointer, as
# `name as fn(int)` does. It named `_aether_bare_adapter_<name>`, which was
# never emitted (gcc: undeclared), and would have handed C a closure struct
# where it reads a function pointer.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

fail() { echo "  [FAIL] extern_fnptr_bare_function: $1"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$AE" build "$SCRIPT_DIR/own.ae" -o "$TMP/own" --extra "$SCRIPT_DIR/apply.c" > "$TMP/build.log" 2>&1 \
    || { cat "$TMP/build.log"; fail "did not build"; }
out="$("$TMP/own" 2>&1)" || { echo "$out"; fail "did not run"; }
expected="got 2
got 3
twice 20"
[ "$out" = "$expected" ] || { echo "$out"; fail "unexpected output"; }

echo "  [PASS] extern_fnptr_bare_function: a bare function is a C function pointer to an extern"
