#!/bin/sh
# #3392, #3396: an actor stepped inside a library call runs outside it. On
# the cooperative runtime an export's ask polls, stepping the asked actor on
# the call's thread: the call's deadline was raised inside the actor's loop
# and caught by the actor's barrier (the actor died, "the call's deadline
# passed"), the interruption stayed marked for the next call (whose try then
# could not catch an ordinary panic), and the actor read the caller info the
# host set for the call. Run on threads by the suite and on the cooperative
# scheduler by make ci-coop; the output is the same on both.
#
# Fixtures, not tests: steps.ae is a library the driver builds and links
# into host.c.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
CC="${CC:-cc}"
export AETHER_HOME="$ROOT"
export AETHER_STACK_TRACE=0

[ -x "$AE" ] || { echo "  [SKIP] emit_lib_actor_step_context: $AE not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT
want='spin: 0 outcome 2, the spinner finished: yes
catch: 1 outcome 0
teller: "" outcome 0'

if ! "$AETHERC" --emit=lib --with=extern,os "$SCRIPT_DIR/steps.ae" "$TMP/steps.c" > "$TMP/steps.log" 2>&1; then
    echo "  [FAIL] emit_lib_actor_step_context: aetherc --emit=lib failed"
    tail -5 "$TMP/steps.log" | sed 's/^/        /'
    exit 1
fi
# shellcheck disable=SC2046
if ! "$CC" -O1 -I"$ROOT/include" -I"$ROOT/runtime" $("$AE" cflags --cflags) \
        "$TMP/steps.c" "$SCRIPT_DIR/host.c" -o "$TMP/host" \
        $("$AE" cflags --libs) > "$TMP/cc.log" 2>&1; then
    echo "  [FAIL] emit_lib_actor_step_context: the host did not build"
    head -10 "$TMP/cc.log" | sed 's/^/        /'
    exit 1
fi
got="$("$TMP/host" 2>"$TMP/host.err" | tr -d '\r')"
if [ "$got" != "$want" ]; then
    echo "  [FAIL] emit_lib_actor_step_context:"
    echo "      got:"; printf '%s\n' "$got" | sed 's/^/        /'
    echo "      want:"; printf '%s\n' "$want" | sed 's/^/        /'
    head -5 "$TMP/host.err" | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] emit_lib_actor_step_context: an actor a call's ask steps runs outside the call: not cut by its deadline, no interruption left for the next call, no caller info of the call"
