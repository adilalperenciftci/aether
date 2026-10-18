#!/bin/sh
# A tuple destructure's local that nothing reads does not fail -Wall -Werror.
#
# `a, _b = pair()` declared `int _b = _tup0._1;` in the C and never read it,
# which is -Wunused-variable, in -Wall for C on gcc and clang. A `_` prefix
# is how a program says a binding is unused, and the type checker does not
# warn about it, but the C compiler did, so -Werror failed. std.fs's
# remove_tree does exactly that (`k, _s, _m, serr = file_stat(path)`), so
# every program calling it failed. Such a local is now written
# `(void)name;` after its declaration, as a guard's binding is.
#
# locals.ae: `_`-prefixed and never-read destructure locals, at the top of
#   main and in a nested block. Its C compiles with -Wall -Werror.
# remove_tree.ae: calls fs.remove_tree. Its C has no unused-variable
#   warning. Unused constants are left to their own tests
#   (static_string_literal_unused, imported_const_unused), so this one
#   passes -Wno-unused-const-variable.
# Both on every one of gcc and clang that is installed; both programs run.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
NAME=destructure_unused_local

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

for prog in locals remove_tree; do
    if ! "$AETHERC" "$SCRIPT_DIR/$prog.ae" "$TMP/$prog.c" >"$TMP/$prog.log" 2>&1; then
        echo "  [FAIL] $NAME: aetherc rejected $prog.ae"
        head -20 "$TMP/$prog.log" | sed 's/^/          /'
        exit 1
    fi
    extra=""
    [ "$prog" = remove_tree ] && extra="-Wno-unused-const-variable"
    for cc in $CCS; do
        # shellcheck disable=SC2086
        if ! "$cc" -c -Wall -Werror $extra $cflags "$TMP/$prog.c" -o "$TMP/$prog.$cc.o" \
                >"$TMP/$prog.$cc.log" 2>&1; then
            echo "  [FAIL] $NAME: $prog.ae's C does not compile with $cc -Wall -Werror $extra"
            grep -E 'error' "$TMP/$prog.$cc.log" | head -10 | sed 's/^/          /'
            fail=1
        fi
    done
done

for prog in locals remove_tree; do
    case "$prog" in
        locals) want="3|3|10" ;;
        remove_tree) want="0" ;;
    esac
    got=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run "$prog.ae" 2>"$TMP/$prog.run.err" |
           tr '\n' '|' | sed 's/|$//' )
    if [ "$got" != "$want" ]; then
        echo "  [FAIL] $NAME: $prog.ae printed '$got', expected '$want'"
        head -10 "$TMP/$prog.run.err" | sed 's/^/          /'
        fail=1
    fi
done

[ "$fail" = 0 ] || exit 1
echo "  [PASS] $NAME: unread destructure locals compile clean under -Wall -Werror on$CCS"
exit 0
