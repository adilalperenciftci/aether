#!/bin/sh
# Locals the generated C declares and nothing reads no longer fail
# -Wall -Werror (-Wunused-variable, in -Wall for C on gcc and clang):
#
#   - a closure env's teardown with nothing to release declared `_e`;
#   - an actor arm that binds no field declared `_pattern`, and one that
#     binds a field it never reads declared the field;
#   - a `_`-prefixed local (`_x = 5`) or one never read (`y = 6`, which the
#     type checker warns about but the C compiler should not fail on);
#   - a `_ = f()` in a loop, hoisted out of it as `int _ = 0;`;
#   - a match whose arms are all `_` declared `_match_val`;
#   - a list pattern's tail declared `<tail>_len` beside the slice.
#
# Each is now followed by `(void)name;`, as a guard's binding and a
# destructure's unread local are. locals.ae has every shape; its C compiles
# with -Wall -Werror on every one of gcc and clang that is installed, and it
# runs. -Wno-unused-function and -Wno-unused-label leave the generated
# static helpers and `main_exit:`, a separate mechanism, to their own test.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
NAME=unused_generated_locals

if [ ! -x "$AETHERC" ] || [ ! -x "$AE" ]; then
    echo "  [SKIP] $NAME: compiler not built"
    exit 0
fi

CCS=""
for cc in gcc clang; do
    command -v "$cc" >/dev/null 2>&1 && CCS="$CCS $cc"
done
if [ -z "$CCS" ]; then
    echo "  [SKIP] $NAME: neither gcc nor clang is installed"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

cflags=$("$AE" cflags --cflags)

if ! "$AETHERC" "$SCRIPT_DIR/locals.ae" "$TMP/locals.c" >"$TMP/locals.log" 2>&1; then
    echo "  [FAIL] $NAME: aetherc rejected locals.ae"
    head -20 "$TMP/locals.log" | sed 's/^/          /'
    exit 1
fi
for cc in $CCS; do
    # shellcheck disable=SC2086
    if ! "$cc" -c -Wall -Werror -Wno-unused-function -Wno-unused-label $cflags \
            "$TMP/locals.c" -o "$TMP/locals.$cc.o" >"$TMP/locals.$cc.log" 2>&1; then
        echo "  [FAIL] $NAME: locals.ae's C does not compile with $cc -Wall -Werror"
        grep -E 'error' "$TMP/locals.$cc.log" | head -12 | sed 's/^/          /'
        fail=1
    fi
done

want="5|42|8|3"
got=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run locals.ae 2>"$TMP/run.err" |
       tr '\n' '|' | sed 's/|$//' )
if [ "$got" != "$want" ]; then
    echo "  [FAIL] $NAME: locals.ae printed '$got', expected '$want'"
    head -10 "$TMP/run.err" | sed 's/^/          /'
    fail=1
fi

[ "$fail" = 0 ] || exit 1
echo "  [PASS] $NAME: unread generated locals compile clean under -Wall -Werror on$CCS"
exit 0
