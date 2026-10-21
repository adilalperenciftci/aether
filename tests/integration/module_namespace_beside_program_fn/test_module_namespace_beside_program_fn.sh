#!/bin/sh
# A module's own import is its namespace, beside a function of the same name
# (#3084). main.ae defines `frame() -> ptr` and imports pkg.user, which
# imports pkg.frame and reads `frame.SETS`. The member access took the
# namespace only when no symbol of the name was in scope, and a module's
# code sees the program's functions, so `frame` was the program's function
# and `frame.SETS` a field of its `ptr` result: since 0.837, where a bare
# `ptr` has no fields (#3048), "Type 'ptr' has no field 'SETS'", in the
# module and in main.ae's own `frame.SETS`. A function has no fields, so it
# hides no namespace; a value of the name still does
# (tests/integration/module_name_local_shadow).
#
# Acceptance: compiles, links, runs, prints "sets 3 7 3 2 true": the module's
# constant read in pkg.user and in main.ae, the module's functions called
# through the namespace, and the program's own `frame()`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] module_namespace_beside_program_fn: $AE not built"
    exit 0
fi

out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run main.ae 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "  [FAIL] module_namespace_beside_program_fn: program errored (rc=$rc)"
    echo "$out" | head -20 | sed 's/^/          /'
    exit 1
fi

got=$(printf '%s\n' "$out" | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -1)
if [ "$got" != "sets 3 7 3 2 true" ]; then
    echo "  [FAIL] module_namespace_beside_program_fn: expected 'sets 3 7 3 2 true', got '$got'"
    echo "$out" | head -20 | sed 's/^/          /'
    exit 1
fi

echo "  [PASS] module_namespace_beside_program_fn: a module's import is its namespace beside a program function of that name"
exit 0
