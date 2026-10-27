#!/bin/sh
# Wycheproof adversarial vector suites: ECDH (#3291).
#
# Every case of ecdh_secp*_ecpoint_test.json: the valid shared secrets, and
# the refusal of points off the curve (the invalid-curve attack), of
# coordinates >= p and of malformed encodings.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$ROOT" || exit 1

AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [FAIL] wycheproof_ecdh: build/ae missing (run make)"; exit 1; }

rc=0
for drv in wp_ecdh_ecpoint; do
    out="$("$AE" run "tests/integration/wycheproof/$drv.ae" 2>&1)"
    if printf '%s' "$out" | grep -q "^ALL PASS"; then
        printf '%s\n' "$out" | grep "^wycheproof" | sed 's/^/  [PASS] /'
    else
        echo "  [FAIL] wycheproof $drv:"
        printf '%s\n' "$out" | tail -12 | sed 's/^/        /'
        rc=1
    fi
done
exit $rc
