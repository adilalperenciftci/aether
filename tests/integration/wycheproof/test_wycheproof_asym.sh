#!/bin/sh
# Wycheproof adversarial vector suites: RSA signatures and X448.
#
# Every case: RSA PKCS#1 v1.5 verify (259) and PSS verify (108), the public
# std.bignum operation, and X448 (510) on the fixed-width field since
# #2600 (stride 25 on std.bignum before). About 6 s at the -O0 of `ae run`.
# (ed25519 rides in test_wycheproof.sh; ECDSA and ECDH have their own
# slots.) WYCHEPROOF_STRIDE=N samples every Nth case.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$ROOT" || exit 1

AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [FAIL] wycheproof_asym: build/ae missing (run make)"; exit 1; }

rc=0
for drv in wp_rsa_pkcs1 wp_rsa_pss wp_x448; do
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
