#!/bin/sh
# A glob import binds every export of a module, however many there are.
#
# The typechecker's import-alias table, which maps each bare name an
# import binds to the qualified name a call is rewritten to, was a fixed
# 512-entry array that dropped entries past the last one without a word. A
# glob import of a wider module (aether-ui's `ui`, about 700 exports) left
# the dropped names bound in the symbol table but not rewritten: the program
# type-checked, and its C called the bare `window(...)`, `vstack(...)` and
# `text(...)`, undeclared, where `import ui (window, vstack, text)` built.
#
# Fixture, generated: lib/wide exports 600 functions `f0` .. `f599` and two
# trailing-block functions with an injected `_ctx` (as ui's `vstack` and
# `text` are). The program glob-imports it and calls the first and last of
# the 600 and the two blocks; which names fell past the table's end
# depended on the symbol table's order, so it calls both ends.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT

mkdir -p "$TMP/lib/wide"
{
    echo "exports ("
    i=0
    while [ "$i" -lt 600 ]; do echo "    f$i,"; i=$((i + 1)); done
    echo "    box, item"
    echo ")"
    i=0
    while [ "$i" -lt 600 ]; do echo "f$i() -> int { return $i }"; i=$((i + 1)); done
    cat <<'AE'
box(_ctx: ptr, n: int) {
    println("box ${n}")
}
item(_ctx: ptr, label: string) {
    println("item ${label}")
}
AE
} >"$TMP/lib/wide/module.ae"

cat >"$TMP/main.ae" <<'AE'
import wide (*)
main() {
    box(1) { item("a") }
    println("${f0()} ${f599()}")
}
AE

cd "$TMP"
out="$("$AE" run main.ae 2>&1)"
expected="box 1
item a
0 599"
if [ "$(printf '%s\n' "$out" | tail -3)" = "$expected" ]; then
    echo "  [PASS] a glob import of a 602-export module binds all of them"
    echo "PASS: glob_import_wide"
    exit 0
fi
echo "  [FAIL] main.ae did not print the expected lines:"
printf '%s\n' "$out" | sed 's/^/        /' | head -10
echo "FAIL: glob_import_wide"
exit 1
