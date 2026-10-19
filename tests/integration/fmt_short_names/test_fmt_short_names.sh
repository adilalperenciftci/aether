#!/bin/sh
# `ae fmt --short-names` writes a call that names its module twice in the
# short form, where the compiler resolves both to the same declaration
# (#2976).
#
# `json.json_free(v)` and `json.free(v)` call the same function, and code
# copied the long form from Aether's own examples. The rewrite takes the
# list from `aetherc --emit=short-names`, so it changes only what the
# compiler says is one declaration: an extern reached by its short name
# (`string.string_length`), an Aether function written in the prefixed form
# (`md5.md5_hex`, reachable as `md5.hex` since #2976), a call inside an
# interpolation, two on one line. It leaves a long name whose short twin is
# another function (std.string's extern `string.string_join` beside its
# `string.join`, #2978), one whose short form would start with a digit
# (`sha3.sha3_256_hex`), and the layout. The rewritten program prints the
# same and compiles to the same C. A file that does not compile keeps its
# names.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT" && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AE" ] || [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] fmt_short_names: toolchain not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
export AETHER_HOME="$ROOT"
fail=0

cat > "$tmp/prog.ae" <<'AE'
import std.json
import std.string
import std.cryptography.md5
import std.cryptography.sha3

main() {
    v, err = json.parse("[1,2]")
    if err != "" { exit(1) }
    n = json.json_array_size(v)
    println("n=${n} ${string.string_length("abc")}")
    json.json_free(v)
    h = md5.md5_hex(string.bytes("a"))
    k = string.string_length(h) + string.string_length("x")
    seq = string.seq_cons("a", string.seq_cons("b", string.seq_empty()))
    j = string.string_join(seq, "-")
    string.seq_free(seq)
    d = sha3.sha3_256_hex(string.bytes("a"))
    println("${h} ${k} ${j} ${string.string_length(d)}")
}
AE

cat > "$tmp/want.ae" <<'AE'
import std.json
import std.string
import std.cryptography.md5
import std.cryptography.sha3

main() {
    v, err = json.parse("[1,2]")
    if err != "" { exit(1) }
    n = json.array_size(v)
    println("n=${n} ${string.length("abc")}")
    json.free(v)
    h = md5.hex(string.bytes("a"))
    k = string.length(h) + string.length("x")
    seq = string.seq_cons("a", string.seq_cons("b", string.seq_empty()))
    j = string.string_join(seq, "-")
    string.seq_free(seq)
    d = sha3.sha3_256_hex(string.bytes("a"))
    println("${h} ${k} ${j} ${string.length(d)}")
}
AE

before="$(cd "$tmp" && "$AE" run prog.ae 2>&1 | tr -d '\r')"
(cd "$tmp" && "$AETHERC" prog.ae before.c >/dev/null 2>&1)
cp "$tmp/prog.ae" "$tmp/orig.ae"
if ! (cd "$tmp" && "$AE" fmt --short-names prog.ae >"$tmp/fmt.log" 2>&1); then
    echo "  [FAIL] fmt_short_names: ae fmt --short-names failed"
    sed 's/^/          /' "$tmp/fmt.log" | head -10
    fail=1
fi
if [ "$(cat "$tmp/want.ae")" != "$(cat "$tmp/prog.ae")" ]; then
    echo "  [FAIL] fmt_short_names: the rewrite differs from the expected one; got:"
    sed 's/^/          /' "$tmp/prog.ae" | head -30
    fail=1
fi
after="$(cd "$tmp" && "$AE" run prog.ae 2>&1 | tr -d '\r')"
if [ -z "$before" ] || [ "$before" != "$after" ]; then
    echo "  [FAIL] fmt_short_names: the program printed '$before' before and '$after' after"
    fail=1
fi
(cd "$tmp" && "$AETHERC" prog.ae after.c >/dev/null 2>&1)
if ! grep -v '^#line' "$tmp/before.c" > "$tmp/before.n" ||
   ! grep -v '^#line' "$tmp/after.c" > "$tmp/after.n" ||
   [ "$(cat "$tmp/before.n")" != "$(cat "$tmp/after.n")" ]; then
    echo "  [FAIL] fmt_short_names: the C differs before and after the rewrite"
    fail=1
fi

# Rewritten once, nothing is left to rewrite; --check says so.
if ! (cd "$tmp" && "$AE" fmt --short-names --check prog.ae >/dev/null 2>&1); then
    echo "  [FAIL] fmt_short_names: --check found more to rewrite after the rewrite"
    fail=1
fi
cp "$tmp/orig.ae" "$tmp/again.ae"
if (cd "$tmp" && "$AE" fmt --short-names --check again.ae >/dev/null 2>&1); then
    echo "  [FAIL] fmt_short_names: --check did not report a file with long names"
    fail=1
fi

# A file the compiler rejects keeps its names.
cat > "$tmp/bad.ae" <<'AE'
import std.json

main() {
    json.json_free(nothing_here)
}
AE
cp "$tmp/bad.ae" "$tmp/bad_orig.ae"
(cd "$tmp" && "$AE" fmt --short-names bad.ae >/dev/null 2>"$tmp/bad.log")
if [ "$(cat "$tmp/bad.ae")" != "$(cat "$tmp/bad_orig.ae")" ]; then
    echo "  [FAIL] fmt_short_names: a file that does not compile was rewritten"
    fail=1
fi
if ! grep -q "does not compile; its names are left as written" "$tmp/bad.log"; then
    echo "  [FAIL] fmt_short_names: no word that the file was left as written"
    fail=1
fi

if [ $fail -eq 0 ]; then
    echo "  [PASS] fmt_short_names: doubled module names shortened where they are one declaration, C unchanged"
fi
exit $fail
