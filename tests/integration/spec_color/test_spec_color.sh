#!/bin/sh
# Regression (#3180): std.spec colours its output only for a terminal.
#
# Every ✓/✗ line and the summary went out wrapped in ANSI escapes, into a
# pipe or a file too and with NO_COLOR set, so a suite's output could not
# be compared or read in a log. Now the colour is decided once: never with
# NO_COLOR set (and not empty), always with FORCE_COLOR set, NO_COLOR
# winning, and otherwise when stdout is a terminal. Here stdout is a file,
# so the plain run must hold no escape at all.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] spec_color: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/suite_test.ae" <<'AEOF'
import std.spec

main() {
    fw = spec.init()
    spec.describe(fw, "colour") {
        spec.it("passes") callback {
            spec.assert_eq(1, 1, "one")
        }
        spec.skip_it("waits", "not yet") callback {
            spec.assert_eq(1, 2, "never run")
        }
    }
    return spec.run_summary(fw)
}
AEOF
if ! (cd "$TMP" && AETHER_HOME="$ROOT" "$AE" build suite_test.ae -o suite) > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] spec_color: the suite does not build"
    sed 's/^/        /' "$TMP/build.log" | head -12
    exit 1
fi
BIN="$TMP/suite"
[ -x "$BIN.exe" ] && BIN="$BIN.exe"

esc=$(printf '\033')
fail=0

# run LABEL WANT ENV...: run the suite with ENV, stdout into a file; WANT is
# "plain" or "colour".
run() {
    label="$1"
    want="$2"
    shift 2
    env "$@" "$BIN" > "$TMP/out.txt" 2>&1
    if grep -q "$esc" "$TMP/out.txt"; then got=colour; else got=plain; fi
    if [ "$got" = "$want" ] && grep -q "1 passing" "$TMP/out.txt"; then
        echo "  [PASS] $label: $want"
    else
        echo "  [FAIL] $label: expected $want output, got $got:"
        sed 's/^/        /' "$TMP/out.txt" | head -12
        fail=1
    fi
}

run "into a file" plain -u NO_COLOR -u FORCE_COLOR
run "NO_COLOR set" plain -u FORCE_COLOR NO_COLOR=1
run "FORCE_COLOR set" colour -u NO_COLOR FORCE_COLOR=1
run "both set" plain NO_COLOR=1 FORCE_COLOR=1
run "NO_COLOR empty" colour NO_COLOR= FORCE_COLOR=1

# The plain form is exactly the text without the escapes.
env -u NO_COLOR -u FORCE_COLOR "$BIN" > "$TMP/plain.txt" 2>&1
want="colour
    ✓ passes
    ⊘ waits  (skipped: not yet)

  1 passing
  1 skipped"
got="$(cat "$TMP/plain.txt")"
if [ "$got" = "$want" ]; then
    echo "  [PASS] the plain output reads as the coloured one, unpainted"
else
    echo "  [FAIL] plain output:"
    printf '%s\n' "$got" | sed 's/^/        /' | head -12
    fail=1
fi

exit $fail
