#!/bin/sh
# #2366: a heap string destructured from a tuple and stored in a struct field
# ends up owned by the field (prog.ae). The program checks its own heap growth
# where the count is exact; it also runs to completion, which would abort on
# a double free, and prints each clip.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] heap_field_destructured_owned: build/ae missing"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT

fail() {
    echo "  [FAIL] heap_field_destructured_owned: $1"
    exit 1
}

# It runs to completion and prints each clip.
AETHER_HOME="$ROOT" "$AE" build "$SCRIPT_DIR/prog.ae" -o "$TMP/prog" > "$TMP/build.log" 2>&1 \
    || { sed 's/^/        /' "$TMP/build.log" | head -8; fail "build failed"; }
"$TMP/prog" > "$TMP/run.out" 2>&1 || { sed 's/^/        /' "$TMP/run.out" | head -8; fail "program aborted"; }
tr -d '\r' < "$TMP/run.out" > "$TMP/run.txt"
for want in clip-0 clip-1 clip-2 done; do
    grep -qx "$want" "$TMP/run.txt" || fail "output lacks '$want'"
done

echo "  [PASS] heap_field_destructured_owned"
