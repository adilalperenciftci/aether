#!/bin/sh
# A @quotable function defined in a module: the quote reaches it under its
# merged name (shlib_length2), and the calls in its body are named as written
# (sqrt), not as the merge renamed them (math_sqrt), as a quote's own calls
# are. A back end maps written names (GLSL's sqrt); a merged C name means
# nothing to it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] quote_helper_module: ae not built"; exit 0; }
out="$(cd "$SCRIPT_DIR" && "$AE" run main.ae --lib lib 2>&1)"
want='(param x :float) (param y :float) (BLOCK (RETURN :float (CALL sqrt :float (BINARY + :float (BINARY * :float (LOCAL x :float) (LOCAL x :float)) (BINARY * :float (LOCAL y :float) (LOCAL y :float))))))
5'
if [ "$out" = "$want" ]; then
    echo "  [PASS] quote_helper_module: a module's @quotable function names its calls as written"
else
    echo "  [FAIL] quote_helper_module: the helper's tree is not as expected"
    echo "      got:";  printf '%s\n' "$out"  | sed 's/^/        |/'
    echo "      want:"; printf '%s\n' "$want" | sed 's/^/        |/'
    exit 1
fi
