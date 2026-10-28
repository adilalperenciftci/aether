#!/bin/sh
# `xs.push(v)` on a module-level `var` grows the global itself (the
# language reference says a module-level `var` is a place push takes):
#
#   - in an imported module, the receiver is the module's own cell: the
#     merge renamed a bare read of `kind` to `views_kind` but left the call
#     `kind.push(k)` bare, and the checker reported "Undefined function
#     'kind.push'";
#   - with a value a call makes (`rows.push(make([]int, 0))`), the receiver
#     is the place, not a copy: the operand-order rule (#2765) held the
#     global in a temporary ahead of the call, and the push grew the copy.
#
# Acceptance -- main.ae prints exactly:
#   3 2      (three views in lib/views.ae, two of them in the first)
#   1 2 1    (this module's log and rows, pushed in place)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run main.ae 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "  [FAIL] slice_push_module_var: program errored (rc=$rc)"
    echo "$out" | head -20 | sed 's/^/          /'
    exit 1
fi

got=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tr '\n' ' ' | sed 's/ *$//')
if [ "$got" != "3 2 1 2 1" ]; then
    echo "  [FAIL] slice_push_module_var: expected '3 2 1 2 1', got '$got'"
    echo "$out" | head -20 | sed 's/^/          /'
    exit 1
fi

echo "  [PASS] slice_push_module_var: a module-level slice grows in place, here and imported"
exit 0
