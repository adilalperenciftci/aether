#!/bin/sh
# `m.x` reaches a module's Aether function written in the prefixed form
# `m_x` (#2976). A qualified name was resolved by joining it into the C
# name `m_x`, so it reached an extern of that name and a function `x`
# (merged as `m_x`), but not a function named `m_x` (merged as `m_m_x`):
# `rexxae.create(...)` against a module's `rexxae_create` and std.md5's
# `md5.hex` were `E0301 Undefined function`, while the long forms built.
# Now the module's declarations are looked up by name: `x`, then the
# prefixed `m_x`, whatever kind of declaration it is. The long forms keep
# working, and a selective import of the short name binds it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
if [ ! -x "$AE" ]; then
    echo "  [SKIP] module_prefixed_form_names: ae not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0

mkdir -p "$tmp/rexxae"
cat > "$tmp/rexxae/module.ae" <<'AE'
exports(rexxae_create, rexxae_twice)

rexxae_create(source: string) -> int {
    return 7
}

rexxae_twice(n: int) -> int {
    return rexxae_create("") * n
}
AE

cat > "$tmp/main.ae" <<'AE'
import rexxae
import std.cryptography.md5
import std.string

main() {
    a = md5.hex(string.bytes("abc"))
    b = md5.md5_hex(string.bytes("abc"))
    println("${rexxae.create("x")} ${rexxae.rexxae_create("x")} ${rexxae.twice(2)} ${a} ${string.equals(a, b)}")
}
AE
out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run main.ae 2>&1 | tr -d '\r' | tail -1)"
if [ "$out" != "7 7 14 900150983cd24fb0d6963f7d28e17f72 1" ]; then
    echo "  [FAIL] module_prefixed_form_names: the short and long forms printed: $out"
    fail=1
fi

cat > "$tmp/sel.ae" <<'AE'
import rexxae(create)

main() {
    println("${create("x")}")
}
AE
out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run sel.ae 2>&1 | tr -d '\r' | tail -1)"
if [ "$out" != "7" ]; then
    echo "  [FAIL] module_prefixed_form_names: a selective import of the short name printed: $out"
    fail=1
fi

if [ $fail -eq 0 ]; then
    echo "  [PASS] module_prefixed_form_names: m.x reaches a module's m_x, an Aether function as an extern"
fi
exit $fail
