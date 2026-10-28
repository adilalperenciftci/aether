#!/bin/sh
# #3388: a call that returns normally but ends with an outcome other than
# AETHER_OK (a stop noted after its last safe point: here an allocation the
# code survived, with no loop after it) returns its zero value, and the
# library releases what it would have returned. It returned its real result
# ("hello7" with outcome 5, 42 with outcome 5), which a host following the
# docs (release only what an AETHER_OK call returned) leaked, and so did an
# Aether importer, whose stub raised the failure before it gave the string
# back to the library.
#
# Fixtures, not tests: results.ae and words.ae are libraries, and app.ae
# imports words.ae (a static library with a struct of strings is refused by
# an importer); the driver builds them.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
CC="${CC:-cc}"
export AETHER_HOME="$ROOT"
export AETHER_STACK_TRACE=0

[ -x "$AE" ] || { echo "  [SKIP] emit_lib_failed_result: $AE not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT
fail=0
want='string NULL outcome 5, released yes
int 0 outcome 5
struct 0 (null) outcome 5, released yes
closure (null) outcome 5, released yes
ok: hello7 42 1 p7 outcome 0'
app_want='raised: the call ran out of memory
the library holds what it held before: true
then: hello7'

case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT) ext=dll; exe=.exe ;;
    Darwin) ext=dylib; exe="" ;;
    *) ext=so; exe="" ;;
esac

if ! "$AETHERC" --emit=lib --with=extern "$SCRIPT_DIR/results.ae" "$TMP/results.c" > "$TMP/results.log" 2>&1; then
    echo "  [FAIL] emit_lib_failed_result: aetherc --emit=lib failed"
    tail -5 "$TMP/results.log" | sed 's/^/        /'
    exit 1
fi
# shellcheck disable=SC2046
if ! "$CC" -O1 -I"$ROOT/include" -I"$ROOT/runtime" $("$AE" cflags --cflags) \
        "$TMP/results.c" "$SCRIPT_DIR/host.c" -o "$TMP/host" \
        $("$AE" cflags --libs) > "$TMP/cc.log" 2>&1; then
    echo "  [FAIL] emit_lib_failed_result: the host did not build"
    head -10 "$TMP/cc.log" | sed 's/^/        /'
    exit 1
fi
got="$("$TMP/host" 2>"$TMP/host.err" | tr -d '\r')"
if [ "$got" != "$want" ]; then
    echo "  [FAIL] emit_lib_failed_result: C host:"
    echo "      got:"; printf '%s\n' "$got" | sed 's/^/        /'
    echo "      want:"; printf '%s\n' "$want" | sed 's/^/        /'
    head -5 "$TMP/host.err" | sed 's/^/        /'
    fail=1
fi

# The importer, the library with a runtime of its own.
mkdir -p "$TMP/imp"
cp "$SCRIPT_DIR/app.ae" "$TMP/imp/app.ae"
if ! (cd "$TMP/imp" && "$AE" build --emit=lib --with=extern "$SCRIPT_DIR/words.ae" \
        -o "$TMP/imp/libwords.$ext" > build.log 2>&1); then
    echo "  [FAIL] emit_lib_failed_result: ae build --emit=lib failed"
    tail -5 "$TMP/imp/build.log" | sed 's/^/        /'
    exit 1
fi
got="$(cd "$TMP/imp" && "$AE" build app.ae -o app > app_build.log 2>&1 && \
       PATH="$TMP/imp:$PATH" LD_LIBRARY_PATH="$TMP/imp${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
       DYLD_LIBRARY_PATH="$TMP/imp${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
       ./app$exe 2>app.err | tr -d '\r')"
if [ "$got" != "$app_want" ]; then
    echo "  [FAIL] emit_lib_failed_result: Aether importer:"
    echo "      got:"; printf '%s\n' "$got" | sed 's/^/        /'
    echo "      want:"; printf '%s\n' "$app_want" | sed 's/^/        /'
    tail -5 "$TMP/imp/app_build.log" "$TMP/imp/app.err" 2>/dev/null | sed 's/^/        /'
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "  [PASS] emit_lib_failed_result: a call that ends at its return with a stop noted returns its zero value, its string, struct and closure released by the library; an importer raises it and keeps nothing"
fi
exit $fail
