#!/bin/sh
# #3016: one rule decides which values have a string rendering, and every
# place that renders one applies it: an interpolation, each `println` /
# `print` argument (the call and the statement form) and print's format
# arguments. A tuple, a struct, a sum and an optional are refused before C;
# they reached it as a `%d` and printed garbage. What has a rendering still
# prints the same everywhere, on both C paths. Pruned from the generic .ae
# runner (the reject_*.ae programs must not compile).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then echo "  [SKIP] render_rule: $AE not built"; exit 0; fi
export AETHER_HOME="$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
CC_BIN="${CC:-cc}"
command -v "$CC_BIN" >/dev/null 2>&1 || CC_BIN=gcc
fail=0

expect_refused() {
    name="$1"; want="$2"
    if "$AETHERC" "$SCRIPT_DIR/$name.ae" "$tmp/$name.c" >"$tmp/$name.log" 2>&1; then
        echo "  [FAIL] render_rule: $name.ae compiled (it must be refused before C)"
        fail=1; return
    fi
    if ! grep -qF "$want" "$tmp/$name.log"; then
        echo "  [FAIL] render_rule: $name.ae refused, but not with: $want"
        sed 's/^/        /' "$tmp/$name.log" | head -6
        fail=1
    fi
}

expect_refused reject_interp_tuple      "cannot interpolate a tuple"
expect_refused reject_print_struct      "cannot print a struct P"
expect_refused reject_print_sum         "cannot print a sum value"
expect_refused reject_print_tuple_call  "cannot print a call that returns 2 values"
expect_refused reject_print_optional    "cannot print an optional"
expect_refused reject_print_format_arg  "cannot print a struct P"
expect_refused reject_print_stmt_tuple  "cannot print a tuple"

want="7 9000000000 1.5 true text 2
7
9000000000
true
text
7|text"
for path in default nogcc; do
    cc=""
    [ "$path" = nogcc ] && cc="$CC_BIN -DAETHER_GCC_COMPAT=0"
    if ! (cd "$SCRIPT_DIR" && AE_CC="$cc" "$AE" build renders.ae -o "$tmp/renders_$path" >"$tmp/build.log" 2>&1); then
        echo "  [FAIL] render_rule: renders.ae did not build ($path):"
        grep -m6 -iE "error" "$tmp/build.log" | sed 's/^/        /'
        fail=1; continue
    fi
    out="$("$tmp/renders_$path" 2>&1 | tr -d '\r')"
    if [ "$out" != "$want" ]; then
        echo "  [FAIL] render_rule: renders.ae printed differently ($path)"
        printf 'got:\n%s\nwant:\n%s\n' "$out" "$want" | sed 's/^/        /'
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] render_rule: tuples, structs, sums and optionals refused in interpolation and print/println; renderable values print the same on both C paths"
fi
exit "$fail"
