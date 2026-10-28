#!/bin/sh
# #2956 (D5): a call's deadline, or a cancel from another thread, ends the
# call instead of cutting a loop short.
#
# A tripped deadline broke the loop it was checked in and the export
# returned what it had, an ordinary-looking value that only
# aether_deadline_tripped() said was partial; a C-backed std operation (a
# large JSON parse) had no check at all and ran to the end; nothing could
# cancel a call from another thread. Now the call ends at a safe point (a
# loop head, or every few thousand units of a long std operation) with
# AETHER_DEADLINE or AETHER_CANCELLED and the zero value; its defers and
# owned locals are released on the way, a `try` in it does not catch the
# interruption, and the library takes the next call.
#
# Fixtures, not tests: work.ae is a library; the driver builds it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
CC="${CC:-cc}"
export AETHER_HOME="$ROOT"

[ -x "$AE" ] || { echo "  [SKIP] emit_lib_interrupt: $AE not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT
want='spin 0 outcome 2 defers 1
guarded 0 outcome 2 defers 2
parse outcome 2
parse 3 outcome 0
cancel 0 outcome 3 defers 3
after -5 outcome 0 defers 4'

if ! "$AETHERC" --emit=lib --with=extern "$SCRIPT_DIR/work.ae" "$TMP/work.c" > "$TMP/work.log" 2>&1; then
    echo "  [FAIL] emit_lib_interrupt: aetherc --emit=lib failed"
    tail -5 "$TMP/work.log" | sed 's/^/        /'
    exit 1
fi
# shellcheck disable=SC2046
if ! "$CC" -O1 -I"$ROOT/include" -I"$ROOT/runtime" $("$AE" cflags --cflags) \
        "$TMP/work.c" "$SCRIPT_DIR/host.c" -o "$TMP/host" \
        $("$AE" cflags --libs) -lpthread > "$TMP/cc.log" 2>&1; then
    echo "  [FAIL] emit_lib_interrupt: the host did not build"
    head -10 "$TMP/cc.log" | sed 's/^/        /'
    exit 1
fi
got="$("$TMP/host" 2>"$TMP/host.err" | tr -d '\r')"
if [ "$got" != "$want" ]; then
    echo "  [FAIL] emit_lib_interrupt:"
    echo "      got:"; printf '%s\n' "$got" | sed 's/^/        /'
    echo "      want:"; printf '%s\n' "$want" | sed 's/^/        /'
    head -5 "$TMP/host.err" | sed 's/^/        /'
    exit 1
fi
# A cancel in a process where nothing was armed when the loop began: the
# loop heads must see the flag another thread sets while they run.
got="$("$TMP/host" cancel-first 2>"$TMP/host.err" | tr -d '\r')"
if [ "$got" != "cancel 0 outcome 3 defers 1" ]; then
    echo "  [FAIL] emit_lib_interrupt: a cancel before any deadline was armed:"
    echo "      got:"; printf '%s\n' "$got" | sed 's/^/        /'
    echo "      want:"; echo "        cancel 0 outcome 3 defers 1"
    head -5 "$TMP/host.err" | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] emit_lib_interrupt: a deadline ends a loop's call with AETHER_DEADLINE and the zero value, defers run, a try does not catch it; a large JSON parse stops early; a cancel from another thread ends the call with AETHER_CANCELLED, armed before or not; the next call works"
