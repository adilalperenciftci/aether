#!/bin/sh
# Wycheproof adversarial vector suites: ECDH (#3291).
#
# Every case of ecdh_secp{256,384,521}r1_ecpoint_test.json and
# ecdh_secp256k1_webcrypto_test.json: the valid shared secrets, and
# the refusal of points off the curve (the invalid-curve attack), of
# coordinates >= p and of malformed encodings: 2,281 key agreements, about
# 30 s at the -O0 of `ae run` (P-521 is half of it).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$ROOT" || exit 1

AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [FAIL] wycheproof_ecdh: build/ae missing (run make)"; exit 1; }

rc=0
for drv in wp_ecdh_ecpoint wp_ecdh_secp256k1; do
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
