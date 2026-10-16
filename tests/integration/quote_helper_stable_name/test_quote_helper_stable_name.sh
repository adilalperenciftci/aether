#!/bin/sh
# A @quotable function's name in a quote's tree, and so the quote's hash, is
# the same in every program (docs/quote.md). pkg.shaders.sky's `decode` is
# `sky_decode` in C when nothing else ends in `sky`, and
# `pkg_shaders_sky_decode` once pkg.sky is loaded too (#2209); the tree used
# to carry that C name, so the same quote hashed differently in two programs
# and ae3d (ae3d.sky beside ae3d.shaders.sky) refused its precompiled SPIR-V.
# The tree names a module's helper by the module's full path and the
# function: `pkg_shaders_sky_decode` in both programs. The CPU call still
# reaches the right function in each.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] quote_helper_stable_name: ae not built"; exit 0; }

one="$(cd "$SCRIPT_DIR" && "$AE" run one.ae --lib lib 2>&1)"
both="$(cd "$SCRIPT_DIR" && "$AE" run both.ae --lib lib 2>&1)"
fail=0
bad() { echo "  [FAIL] quote_helper_stable_name: $1"; fail=1; }

# Lines: hash, helper name, the tree, decode(3.0) [, pkg.sky's decode(3.0)].
name_one=$(printf '%s\n' "$one" | sed -n 2p)
name_both=$(printf '%s\n' "$both" | sed -n 2p)
[ "$name_one" = "pkg_shaders_sky_decode" ] && [ "$name_both" = "pkg_shaders_sky_decode" ] \
    || bad "the helper is not named pkg_shaders_sky_decode in both programs"
[ "$(printf '%s\n' "$one" | sed -n 1p)" = "$(printf '%s\n' "$both" | sed -n 1p)" ] \
    || bad "quote.hash differs between the two programs"
[ "$(printf '%s\n' "$one" | sed -n 3p)" = "$(printf '%s\n' "$both" | sed -n 3p)" ] \
    || bad "the trees differ between the two programs"
case "$(printf '%s\n' "$one" | sed -n 3p)" in
    *"HELPER_CALL pkg_shaders_sky_decode"*) ;;
    *) bad "the HELPER_CALL does not name pkg_shaders_sky_decode" ;;
esac
[ "$(printf '%s\n' "$one" | sed -n 4p)" = "7" ] && [ "$(printf '%s\n' "$both" | sed -n 4p)" = "7" ] \
    && [ "$(printf '%s\n' "$both" | sed -n 5p)" = "2" ] \
    || bad "a CPU call reached the wrong function"

if [ $fail -ne 0 ]; then
    echo "      one.ae:";  printf '%s\n' "$one"  | sed 's/^/        |/'
    echo "      both.ae:"; printf '%s\n' "$both" | sed 's/^/        |/'
    exit 1
fi
echo "  [PASS] quote_helper_stable_name: a module helper's tree name and the quote's hash are the same in every program"
