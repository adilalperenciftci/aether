#!/bin/sh
# Wycheproof adversarial vector suites — ECDSA P-384 (P1363 + DER forms), wave 5.
#
# Every vector of both files (280 + 504 cases), about 8 s at the -O0 of
# `ae run` since #2600 (a P-384 verify is two fixed-width scalar
# multiplications in one pass). WYCHEPROOF_STRIDE=N samples every Nth case.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$ROOT" || exit 1

AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [FAIL] wycheproof_ecdsa_p384: build/ae missing (run make)"; exit 1; }

rc=0
for drv in wp_ecdsa_p384 wp_ecdsa_p384_der; do
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
