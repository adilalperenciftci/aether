#!/bin/sh
# #3375: AETHER_VERBOSE=1 prints the runtime configuration once when the
# scheduler starts, whatever the program was compiled with.
#
# The variable only set a flag nothing read: the configuration was printed
# by a program compiled with -DAETHER_VERBOSE alone, and docs/runtime-config.md
# promised it for `AETHER_VERBOSE=1 ./program`. Now the runtime prints it when
# the variable is set; a program compiled with -DAETHER_VERBOSE still prints
# it, once also when the variable is set too, and nothing is printed when
# neither asks.
#
# Fixture, not a test: counter.ae is built by this driver.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
CC="${CC:-cc}"
export AETHER_HOME="$ROOT"

[ -x "$AE" ] || { echo "  [SKIP] verbose_env: $AE not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT

if ! "$AETHERC" "$SCRIPT_DIR/counter.ae" "$TMP/counter.c" > "$TMP/aetherc.log" 2>&1; then
    echo "  [FAIL] verbose_env: aetherc failed"
    tail -5 "$TMP/aetherc.log" | sed 's/^/        /'
    exit 1
fi
for v in plain defined; do
    def=""; [ $v = defined ] && def="-DAETHER_VERBOSE"
    # shellcheck disable=SC2046
    if ! "$CC" -O1 $def $("$AE" cflags --cflags) "$TMP/counter.c" -o "$TMP/$v" \
            $("$AE" cflags --libs) > "$TMP/cc_$v.log" 2>&1; then
        echo "  [FAIL] verbose_env: the $v program did not build"
        head -10 "$TMP/cc_$v.log" | sed 's/^/        /'
        exit 1
    fi
done

fail=0
# $1 program, $2 AETHER_VERBOSE or "", $3 prints expected
check() {
    if [ -n "$2" ]; then out=$(AETHER_VERBOSE="$2" "$TMP/$1" 2>&1 | tr -d '\r')
    else out=$(env -u AETHER_VERBOSE "$TMP/$1" 2>&1 | tr -d '\r'); fi
    n=$(printf '%s\n' "$out" | grep -c "=== Aether Runtime Configuration ===")
    if [ "$n" != "$3" ] || ! printf '%s\n' "$out" | grep -q "^count 2$"; then
        echo "  [FAIL] verbose_env: $1 program, AETHER_VERBOSE='$2': $n configuration prints, want $3"
        printf '%s\n' "$out" | head -8 | sed 's/^/        /'
        fail=1
    fi
}
check plain "" 0
check plain 1 1
check defined "" 1
check defined 1 1
[ $fail -eq 0 ] && echo "  [PASS] verbose_env: AETHER_VERBOSE prints the configuration once at startup, as -DAETHER_VERBOSE does, and nothing is printed when neither asks"
exit $fail
