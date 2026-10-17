#!/bin/sh
# An imported module's constant reaches the C only when the program names it.
#
# Every `const` of every imported module was a file-scope `static const` in
# the generated C, named or not: `import std.fs` alone gave a program
# fourteen unused `ae_const_fs_KIND_*` (since 0.778.0), each
# -Wunused-const-variable, which -Wall turns on for C on gcc and clang, so
# the program could not be built with -Wall -Werror. The sweep that drops
# the imported functions nothing reaches now drops those constants too.
#
# none_used.ae: imports std.fs and std.json, names no constant: the C has
#   none of theirs.
# some_used.ae: names fs.KIND_EXISTS: that one is kept, the rest are not.
# reached.ae: names none, but calls fs.remove_tree, whose body names
#   STAT_KIND_DIR: that one is kept with the function.
# The programs hold no string literal, so this does not lean on the literal
# statics being left out (static_string_literal_unused). none_used and
# some_used compile with -Wall -Werror on every one of gcc and clang that is
# installed; reached with no warning about a constant (fs.remove_tree has
# unused tuple locals of its own). Each program prints what it should.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
NAME=imported_const_unused

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

for prog in none_used some_used reached; do
    if ! "$AETHERC" "$SCRIPT_DIR/$prog.ae" "$TMP/$prog.c" >"$TMP/$prog.log" 2>&1; then
        echo "  [FAIL] $NAME: aetherc rejected $prog.ae"
        head -20 "$TMP/$prog.log" | sed 's/^/          /'
        exit 1
    fi
    for cc in $CCS; do
        if [ "$prog" = reached ]; then
            # fs.remove_tree's own C has unused locals of another kind
            # (`_s, _m` of a tuple it destructures), so this one is held to
            # no warning about a constant rather than to none at all.
            # shellcheck disable=SC2086
            if ! "$cc" -c -Wall $cflags "$TMP/$prog.c" -o "$TMP/$prog.$cc.o" \
                    >"$TMP/$prog.$cc.log" 2>&1 ||
               grep -q 'ae_const_' "$TMP/$prog.$cc.log"; then
                echo "  [FAIL] $NAME: $prog.ae's C warns about a constant under $cc -Wall"
                grep -E 'error|warning' "$TMP/$prog.$cc.log" | head -10 | sed 's/^/          /'
                fail=1
            fi
            continue
        fi
        # shellcheck disable=SC2086
        if ! "$cc" -c -Wall -Werror $cflags "$TMP/$prog.c" -o "$TMP/$prog.$cc.o" \
                >"$TMP/$prog.$cc.log" 2>&1; then
            echo "  [FAIL] $NAME: $prog.ae's C does not compile with $cc -Wall -Werror"
            grep -E 'error' "$TMP/$prog.$cc.log" | head -10 | sed 's/^/          /'
            fail=1
        fi
    done
done

consts() { grep -oE '^static const [a-z]+ ae_const_(fs|json)_[A-Z_]+' "$1" | sed 's/.* //' | sort | tr '\n' ' ' | sed 's/ $//'; }

got=$(consts "$TMP/none_used.c")
if [ -n "$got" ]; then
    echo "  [FAIL] $NAME: none_used.ae's C still defines: $got"
    fail=1
fi
got=$(consts "$TMP/some_used.c")
if [ "$got" != "ae_const_fs_KIND_EXISTS" ]; then
    echo "  [FAIL] $NAME: some_used.ae's C defines '$got', expected only ae_const_fs_KIND_EXISTS"
    fail=1
fi
got=$(consts "$TMP/reached.c")
if [ "$got" != "ae_const_fs_STAT_KIND_DIR" ]; then
    echo "  [FAIL] $NAME: reached.ae's C defines '$got', expected only ae_const_fs_STAT_KIND_DIR"
    fail=1
fi

for prog in none_used some_used reached; do
    case "$prog" in
        none_used) want="7" ;;
        some_used) want="3" ;;
        reached) want="0" ;;
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
echo "  [PASS] $NAME: only the imported constants a program names reach the C; no constant warning on$CCS"
exit 0
