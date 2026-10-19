#!/bin/sh
# `ae fmt` spaces what follows an optional type as what follows the type
# (#2842).
#
# A closure's parameters are written `| s: Shape |`, but `|o: int?|` came
# out as `| o: int?|`: the formatter kept the author's spacing on both
# sides of every `?`, since a `?` is also the actor ask. A `?` written
# tight after a name or a `)` is a type's optional suffix, and the token
# after it now takes the spacing it would take after the type: the closing
# `|` its space, a `{` its space, a `,` or a `)` none. An ask (`a ? Q {}`)
# keeps the author's spacing.
#
# The input and the expected output are here rather than as .ae files, so
# the fmt gate and the .ae sweep do not pick them up.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] fmt_optional_type_suffix: ae not built"
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat >"$TMPDIR/in.ae" <<'EOF'
pick(o: int?, d: int) -> int? {
    return o
}

main() {
    h = |o: int?| {
        return o ?? 7
    }
    g = |a: int, o: string?| {
        return o ?? "none"
    }
    let k: int? = pick(none, 1)
    println("${call(h, 3)} ${call(g, 1, none)} ${k ?? 9}")
}
EOF

cat >"$TMPDIR/want.ae" <<'EOF'
pick(o: int?, d: int) -> int? {
    return o
}

main() {
    h = | o: int? | {
        return o ?? 7
    }
    g = | a: int, o: string? | {
        return o ?? "none"
    }
    let k: int? = pick(none, 1)
    println("${call(h, 3)} ${call(g, 1, none)} ${k ?? 9}")
}
EOF

cp "$TMPDIR/in.ae" "$TMPDIR/got.ae"
if ! "$AE" fmt "$TMPDIR/got.ae" >"$TMPDIR/fmt.log" 2>&1; then
    echo "  [FAIL] fmt_optional_type_suffix: ae fmt failed"
    sed 's/^/          /' "$TMPDIR/fmt.log" | head -10
    exit 1
fi
if [ "$(cat "$TMPDIR/want.ae")" != "$(cat "$TMPDIR/got.ae")" ]; then
    echo "  [FAIL] fmt_optional_type_suffix: output differs from the expected layout; got:"
    sed 's/^/          /' "$TMPDIR/got.ae" | head -30
    exit 1
fi

cp "$TMPDIR/want.ae" "$TMPDIR/again.ae"
"$AE" fmt "$TMPDIR/again.ae" >/dev/null 2>&1
if [ "$(cat "$TMPDIR/want.ae")" != "$(cat "$TMPDIR/again.ae")" ]; then
    echo "  [FAIL] fmt_optional_type_suffix: formatting the output again changed it"
    exit 1
fi

echo "  [PASS] fmt_optional_type_suffix: a closure's optional last parameter closes as | o: int? |"
exit 0
