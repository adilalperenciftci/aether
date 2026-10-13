#!/bin/sh
# A module-qualified struct type in its pointer form, `*mod.T`, in every
# position a type is written: a return type, a parameter, a struct field, an
# `as` cast and the typed declarations (`let s: *mod.T`, `*mod.T s = ...`).
# `mod.T` already parsed (#946); `*mod.T` stopped at the `.` with "Expected
# LEFT_BRACE, got DOT" / "Expected statement in block", so a consumer had to
# add a selective `import mod (T)` and write `*T` (ae3d's `*gpu.GpuShader`).
#
# The qualifier is also held to what it names now. `mod.Missing` was taken as
# the bare struct `Missing` and reached the C compiler as an unknown type
# name; it is a type error naming the module and the type, as are a
# qualifier that names no imported module and a type the module does not
# export.
#
# Fixture: lib/gpu.ae (GpuShader, Pass, the unexported Scratch); main.ae uses
# them; missing.ae, unimported.ae and unexported.ae each hold one error.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
fail=0

out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run main.ae 2>&1 )
got=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tr '\n' ' ' | sed 's/ *$//')
if [ "$got" != "fxaa#7@2 8" ]; then
    echo "  [FAIL] qualified_ptr_type: expected 'fxaa#7@2 8', got:"
    echo "$out" | head -20 | sed 's/^/          /'
    fail=1
fi

# expect_error FILE LINE MESSAGE: the build fails, at FILE:LINE, with MESSAGE
expect_error() {
    out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" build "$1" -o "${TMPDIR:-/tmp}/qpt_$$" 2>&1 )
    rc=$?
    rm -f "${TMPDIR:-/tmp}/qpt_$$"
    if [ "$rc" -eq 0 ] || ! printf '%s\n' "$out" | grep -qF -- "$3" ||
       ! printf '%s\n' "$out" | grep -qF -- "--> $1:$2:"; then
        echo "  [FAIL] qualified_ptr_type: $1 should fail at line $2 with: $3"
        echo "$out" | head -12 | sed 's/^/          /'
        fail=1
    fi
}
expect_error missing.ae 3 "module 'gpu' has no type 'Missing'"
expect_error unimported.ae 3 "unknown module 'render' in the type 'render.GpuShader'"
expect_error unexported.ae 4 "'Scratch' is not exported from module 'gpu'"

[ "$fail" -eq 0 ] || exit 1
echo "  [PASS] qualified_ptr_type: *mod.T in every type position; a qualifier names a module that exports the type"
exit 0
