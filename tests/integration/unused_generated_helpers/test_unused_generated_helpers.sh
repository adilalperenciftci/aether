#!/bin/sh
# The static helpers the generated C defines for a closure, an actor or a
# struct, and main's `main_exit:` label, no longer fail -Wall -Werror when
# the program does not use them.
#
# Each closure env got `_closure_env_<N>_free`, each actor
# `_aether_init_handlers_<A>`, each owning struct a family of
# `_aether_<op>_<S>` helpers, and every program with actors `rdtsc` and the
# reply-buffer releases, all `static`, whether called or not: unused, each
# is -Wunused-function, in -Wall for C on gcc and clang. They now carry
# AETHER_MAYBE_UNUSED, as the imported wrappers, `_publish` and `_udrop`
# already did (the prelude's note: the storage class carries the attribute
# so that a consumer does not need a -Wno flag). A main with actors and no
# `return` wrote `main_exit:` with no goto to it, -Wunused-label; the label
# is now written only when a goto targets it.
#
# helpers.ae has a closure, an actor and an owning struct and no `return`
# in main. Its C compiles with -Wall -Werror on every one of gcc and clang
# that is installed, and it runs. -Wno-unused-variable and
# -Wno-unused-but-set-variable leave unread locals, a separate mechanism, to
# unused_generated_locals.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
NAME=unused_generated_helpers

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

if ! "$AETHERC" "$SCRIPT_DIR/helpers.ae" "$TMP/helpers.c" >"$TMP/helpers.log" 2>&1; then
    echo "  [FAIL] $NAME: aetherc rejected helpers.ae"
    head -20 "$TMP/helpers.log" | sed 's/^/          /'
    exit 1
fi
if grep -q 'main_exit:' "$TMP/helpers.c"; then
    echo "  [FAIL] $NAME: helpers.ae's C writes main_exit: with no goto to it"
    fail=1
fi
for cc in $CCS; do
    # shellcheck disable=SC2086
    if ! "$cc" -c -Wall -Werror -Wno-unused-variable -Wno-unused-but-set-variable $cflags \
            "$TMP/helpers.c" -o "$TMP/helpers.$cc.o" >"$TMP/helpers.$cc.log" 2>&1; then
        echo "  [FAIL] $NAME: helpers.ae's C does not compile with $cc -Wall -Werror"
        grep -E 'error' "$TMP/helpers.$cc.log" | head -12 | sed 's/^/          /'
        fail=1
    fi
done

want="5|2|3"
got=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run helpers.ae 2>"$TMP/run.err" |
       tr '\n' '|' | sed 's/|$//' )
if [ "$got" != "$want" ]; then
    echo "  [FAIL] $NAME: helpers.ae printed '$got', expected '$want'"
    head -10 "$TMP/run.err" | sed 's/^/          /'
    fail=1
fi

[ "$fail" = 0 ] || exit 1
echo "  [PASS] $NAME: unused generated helpers and main_exit compile clean under -Wall -Werror on$CCS"
exit 0
