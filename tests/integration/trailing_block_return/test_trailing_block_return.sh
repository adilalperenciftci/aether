#!/bin/sh
# Regression for #2766: a `return` with a value inside a call's trailing block
# returns from the function around it, and every walk that asks what that
# function returns now counts it.
#
# main.ae: a function whose only value return is in a builder's block is a
# function that returns a value (it was emitted `void`, and gcc stopped at
# "'return' with a value, in function returning void"), and a bare call
# returned there resolves through the block's receiver when the compiler
# settles which functions return a value: `return note(n)` is blk.note, which
# returns nothing, `return size()` is blk.size, which returns an int.
#
# missing_return.ae: once those returns count, a function that returns a
# value from a block on one path and runs off its end on another is the
# missing-return error, not a C error.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] trailing_block_return: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

out=$(cd "$SCRIPT_DIR" && AETHER_HOME="$ROOT" "$AE" run main.ae 2>&1)
rc=$?
if [ $rc -ne 0 ]; then
    echo "  [FAIL] trailing_block_return: main.ae did not build and run (exit $rc)"
    echo "$out" | sed 's/^/        /'
    fails=$((fails + 1))
else
    for want in "first 10" "sized 103"; do
        case "$out" in
            *"$want"*) ;;
            *) echo "  [FAIL] trailing_block_return: no \"$want\" in:"
               echo "$out" | sed 's/^/        /'
               fails=$((fails + 1)) ;;
        esac
    done
fi

cat > "$TMP/missing_return.ae" <<'AE'
wrap(tag: int) -> int {
    return tag
}

maybe(n: int) {
    wrap(1) {
        if n > 0 {
            return n
        }
    }
}

main() {
    println("${maybe(1)}")
}
AE
out=$(cd "$TMP" && "$AE" check missing_return.ae 2>&1)
if [ $? -eq 0 ]; then
    echo "  [FAIL] trailing_block_return: missing_return.ae accepted"
    echo "$out" | sed 's/^/        /'
    fails=$((fails + 1))
else
    case "$out" in
        *"missing return: control can reach the end of 'maybe'"*) ;;
        *) echo "  [FAIL] trailing_block_return: missing_return.ae: not the missing-return error:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
fi

[ "$fails" -eq 0 ] || exit 1
echo "  [PASS] trailing_block_return: a return in a trailing block is the function's"
