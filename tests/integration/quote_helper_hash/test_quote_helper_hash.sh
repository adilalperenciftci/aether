#!/bin/sh
# quote.hash covers every @quotable function a quote reaches (docs/quote.md,
# version 2): edit a helper's body, even one reached only through another
# helper, and the hash of each quote calling it changes, so a back end's
# cache keyed on it (ae3d's hash-keyed SPIR-V) goes stale with the edit.
# Leaving the helpers alone and editing a function no quote reaches keeps it.
#
# Two builds of one program are needed: inside one program, two quotes that
# call differently-named helpers already differ by the call's name.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] quote_helper_hash: ae not built"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT

# <weight in sq> <weight in luma> <plain's constant>
prog() {
    cat <<AE
import std.quote

q(t: quote.Tree) -> quote.Tree { return t }

@quotable
sq(x: float) -> float {
    return x * x * $1
}

@quotable
luma(r: float, g: float, b: float) -> float {
    return sq(r) * $2 + g * 0.587 + b * 0.114
}

plain(x: float) -> float {
    return x + $3
}

main() {
    t = q() quote | r: float | {
        return luma(r, r, r)
    }
    println("\${quote.hash(t)}")
    println("\${plain(1.0)}")
    quote.free(t)
}
AE
}

hash_of() {   # <name> <sq weight> <luma weight> <plain constant>
    prog "$2" "$3" "$4" > "$tmp/$1.ae"
    "$AE" run "$tmp/$1.ae" > "$tmp/$1.out" 2>&1 || { sed 's/^/        /' "$tmp/$1.out" | head -5; echo "BUILD-FAILED"; return; }
    head -1 "$tmp/$1.out"
}

base=$(hash_of base 1.0 0.299 1.0)
luma_edit=$(hash_of luma_edit 1.0 0.3 1.0)
sq_edit=$(hash_of sq_edit 2.0 0.299 1.0)
plain_edit=$(hash_of plain_edit 1.0 0.299 2.0)

fail=0
case "$base" in ""|*FAILED*) echo "  [FAIL] quote_helper_hash: the base program did not run: $base"; exit 1 ;; esac
[ "$luma_edit" != "$base" ] || { echo "  [FAIL] quote_helper_hash: editing luma's body left the hash at $base"; fail=1; }
[ "$sq_edit" != "$base" ] || { echo "  [FAIL] quote_helper_hash: editing sq (reached only through luma) left the hash at $base"; fail=1; }
[ "$plain_edit" = "$base" ] || { echo "  [FAIL] quote_helper_hash: editing a function no quote reaches changed the hash ($base -> $plain_edit)"; fail=1; }
[ "$fail" -eq 0 ] && echo "  [PASS] quote_helper_hash: a helper's body, direct or reached through another helper, is in the quote's hash; an unreached function is not"
[ "$fail" -eq 0 ]
