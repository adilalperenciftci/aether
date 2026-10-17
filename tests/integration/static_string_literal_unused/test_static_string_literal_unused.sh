#!/bin/sh
# A string literal's static pinned AetherString (`_ae_slit_<i>`, R1 of the
# ownership model) is written only when the C names it.
#
# Since 0.818 every literal of the program got one, even a literal every use
# of which is written as plain C characters: `println("x")` is `puts("x")`.
# The unused `static const _AeStaticStr _ae_slit_<i>` is
# -Wunused-const-variable, which -Wall turns on for C on gcc and clang, so a
# program built with -Wall -Werror failed to compile (found by
# fight-flash-fraud-port's bump to 0.823). The definitions now go in once the
# program is written, for the literals it names: the pinned string, or only
# its bytes where that is all the C reads (a literal holding a NUL, given to
# an extern).
#
# plain.ae: every literal is plain characters, so the C has none of them.
# mixed.ae: one literal needs the pinned string, one only its bytes, one
# neither. Each C file compiles with -Wall -Werror on every one of gcc and
# clang that is installed, and both programs print what they should.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
NAME=static_string_literal_unused

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

# The compile flags `ae cflags` gives, without its link flags.
cflags=$("$AE" cflags --cflags)

for prog in plain mixed; do
    if ! "$AETHERC" "$SCRIPT_DIR/$prog.ae" "$TMP/$prog.c" >"$TMP/$prog.log" 2>&1; then
        echo "  [FAIL] $NAME: aetherc rejected $prog.ae"
        head -20 "$TMP/$prog.log" | sed 's/^/          /'
        exit 1
    fi
    for cc in $CCS; do
        # shellcheck disable=SC2086
        if ! "$cc" -c -Wall -Werror $cflags "$TMP/$prog.c" -o "$TMP/$prog.$cc.o" \
                >"$TMP/$prog.$cc.log" 2>&1; then
            echo "  [FAIL] $NAME: $prog.ae's C does not compile with $cc -Wall -Werror"
            grep -E 'error' "$TMP/$prog.$cc.log" | head -10 | sed 's/^/          /'
            fail=1
        fi
    done
done

# plain.ae names no literal's static.
if grep -n '_ae_slit_' "$TMP/plain.c" >"$TMP/plain.slit"; then
    echo "  [FAIL] $NAME: plain.ae's C still defines a literal's static:"
    head -5 "$TMP/plain.slit" | sed 's/^/          /'
    fail=1
fi

# mixed.ae: "kept" as a pinned string, "a\0b" as its bytes only, "plain" not
# at all.
if ! grep -qE '^static const char _ae_slit_[0-9]+_bytes\[\] = "kept";' "$TMP/mixed.c" ||
   ! grep -qE '^static const _AeStaticStr _ae_slit_[0-9]+ = \{.*, 4, 5, ' "$TMP/mixed.c"; then
    echo "  [FAIL] $NAME: mixed.ae's C lost the pinned string of \"kept\""
    fail=1
fi
nul=$(grep -cE '^static const char _ae_slit_[0-9]+_bytes\[\] = "a\\000b";' "$TMP/mixed.c")
if [ "$nul" != "1" ] || grep -qE '^static const _AeStaticStr _ae_slit_[0-9]+ = \{.*, 3, 4, ' "$TMP/mixed.c"; then
    echo "  [FAIL] $NAME: mixed.ae's C should hold the NUL-holding literal's bytes and not its pinned string"
    fail=1
fi
if grep -qE '_ae_slit_[0-9]+_bytes\[\] = "plain";' "$TMP/mixed.c"; then
    echo "  [FAIL] $NAME: mixed.ae's C defines a static for \"plain\", written as puts(\"plain\")"
    fail=1
fi

# And the programs still do what they say.
want_plain="Usage:|  plain [options]|3"
want_mixed="plain|kept 4|1"
for prog in plain mixed; do
    out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run "$prog.ae" 2>"$TMP/$prog.run.err" )
    got=$(printf '%s\n' "$out" | tr '\n' '|' | sed 's/|$//')
    if [ "$prog" = plain ]; then want="$want_plain"; else want="$want_mixed"; fi
    if [ "$got" != "$want" ]; then
        echo "  [FAIL] $NAME: $prog.ae printed '$got', expected '$want'"
        head -10 "$TMP/$prog.run.err" | sed 's/^/          /'
        fail=1
    fi
done

[ "$fail" = 0 ] || exit 1
echo "  [PASS] $NAME: only the literals the C names get a static; -Wall -Werror is clean on$CCS"
exit 0
