#!/bin/sh
# Wycheproof adversarial vector suites — ECDSA P-521 (P1363 + DER forms), wave 5.
#
# Every vector of both files (318 + 542 cases), about 18 s at the -O0 of
# `ae run`. A P-521 verify took seconds while std.bignum divided a bit at a
# time (stride 40), about 60 ms with Algorithm D (#2595, stride 10), and a
# few milliseconds on the fixed-width engine of #2600. WYCHEPROOF_STRIDE=N
# samples every Nth case.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$ROOT" || exit 1

AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [FAIL] wycheproof_ecdsa_p521: build/ae missing (run make)"; exit 1; }

rc=0
for drv in wp_ecdsa_p521 wp_ecdsa_p521_der; do
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
