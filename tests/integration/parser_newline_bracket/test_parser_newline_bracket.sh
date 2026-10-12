#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# A directory of its own, not fixed /tmp paths: two sweeps at once (two
# checkouts, or parallel agents) overwrote each other's files (#2770).
AE_TMP="$(mktemp -d)"
trap 'rm -rf "$AE_TMP"' EXIT
SRC="$AE_TMP/ae_528_newline_bracket.ae"
OUT="$AE_TMP/ae_528_newline_bracket.c"

cat > "$SRC" <<'AEOF'
main() {
    data = [10, 20, 30]
    [1 + 1, 99]
    println("OK")
}
AEOF

"$ROOT/build/aetherc" "$SRC" "$OUT"

if grep -Fq 'data[1 + 1' "$OUT"; then
    echo "FAIL: newline-led bracket folded into previous data[...] expression"
    exit 1
fi

# The elements are emitted as discarded expressions, one statement each: a
# braced initializer is not a C statement, and emitting one produced generated
# C that did not compile (this test asserted on the text and never built it,
# which is how that survived).
if ! grep -Fq '(void)(2);' "$OUT"; then
    echo "FAIL: newline-led array literal statement was not emitted separately"
    exit 1
fi

# Build it. Asserting on the emitted text alone cannot tell "separate
# statement" from "separate statement that no C compiler accepts".
BIN="$AE_TMP/ae_528_newline_bracket_bin"
if ! "$ROOT/build/ae" build "$SRC" -o "$BIN" >$AE_TMP/ae_528_newline_bracket.log 2>&1; then
    echo "FAIL: the generated C does not compile"
    sed 's/^/        /' $AE_TMP/ae_528_newline_bracket.log | head -10
    exit 1
fi
if [ "$("$BIN")" != "OK" ]; then
    echo "FAIL: the built program did not print OK"
    exit 1
fi
rm -f "$BIN" $AE_TMP/ae_528_newline_bracket.log

echo "PASS parser newline bracket"
