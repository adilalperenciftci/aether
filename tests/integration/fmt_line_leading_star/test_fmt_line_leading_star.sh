#!/bin/sh
# `ae fmt` writes a `*` that begins a line as the prefix it is.
#
# A `*` after a token that ends a value is read as multiplication and gets
# spaces around it. A statement on the line after a call ends the previous
# line with `)`, so the formatter rewrote the typed pointer declaration
# `*Ops p = ...` as `* Ops p = ...`, a deref store `*p = v` as `* p = v`,
# and the qualified `*gpu.GpuShader t` as `* gpu.GpuShader t`. A `*` that
# is its line's first token starts a statement and is a prefix. A `*` in
# the middle of a line keeps the infix spacing.
#
# The input and the expected output are here rather than as .ae files, so
# the fmt gate and the .ae sweep do not pick them up.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] fmt_line_leading_star: ae not built"
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/in.ae" <<'EOF'
main() {
    x = make_ops()
    *Ops p = x as *Ops
    *gpu.GpuShader t = compile(8)
    *p = 3
    y = a * b
    z = f() *g()
}
EOF

cat >"$TMPDIR/want.ae" <<'EOF'
main() {
    x = make_ops()
    *Ops p = x as *Ops
    *gpu.GpuShader t = compile(8)
    *p = 3
    y = a * b
    z = f() * g()
}
EOF

cp "$TMPDIR/in.ae" "$TMPDIR/got.ae"
if ! "$AE" fmt "$TMPDIR/got.ae" >"$TMPDIR/fmt.log" 2>&1; then
    echo "  [FAIL] fmt_line_leading_star: ae fmt failed"
    sed 's/^/          /' "$TMPDIR/fmt.log" | head -10
    exit 1
fi
if [ "$(cat "$TMPDIR/want.ae")" != "$(cat "$TMPDIR/got.ae")" ]; then
    echo "  [FAIL] fmt_line_leading_star: output differs from the expected layout; got:"
    sed 's/^/          /' "$TMPDIR/got.ae" | head -20
    exit 1
fi

cp "$TMPDIR/got.ae" "$TMPDIR/again.ae"
"$AE" fmt "$TMPDIR/again.ae" >/dev/null 2>&1
if [ "$(cat "$TMPDIR/got.ae")" != "$(cat "$TMPDIR/again.ae")" ]; then
    echo "  [FAIL] fmt_line_leading_star: formatting is not idempotent"
    exit 1
fi

echo "  [PASS] fmt_line_leading_star: a line-leading * is a prefix; an infix * keeps its spaces"
exit 0
