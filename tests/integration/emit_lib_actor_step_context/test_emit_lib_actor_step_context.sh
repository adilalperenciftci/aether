#!/bin/sh
# #3392, #3396, #3404: an actor stepped inside a library call runs outside it. On
# the cooperative runtime an export's ask polls, stepping the asked actor on
# the call's thread: the call's deadline was raised inside the actor's loop
# and caught by the actor's barrier (the actor died, "the call's deadline
# passed"), the interruption stayed marked for the next call (whose try then
# could not catch an ordinary panic), and the actor read the caller info the
# host set for the call. Run on threads by the suite and on the cooperative
# scheduler by make ci-coop; the output is the same on both. Last, a kill
# whose message drop runs a loop past the call's deadline (on the cooperative
# runtime the kill finalizes there and then): the interruption was caught
# as the drop's panic and left on its way, so the next call's try could not
# catch an ordinary panic (#3404). The kill's own call must end with what
# its drop raised inside it, and normally where the drop runs on a core's
# thread (#3415): with the deadline, and with a cancel, which trips no flag
# of its own, so that a fix that dropped the interruption (the call then
# ended normally, which the next call's try alone could not tell) fails
# here. Then a kill in a defer that the deadline's unwind runs, whose drop
# panics ordinarily: the panic was taken for the interruption, which was
# then lost, so the call ended PANICKED and a try on the way ran its handler
# (#3415).
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
teller: "" outcome 0
a kill: the call'"'"'s outcome is its drop'"'"'s: yes
after a kill: catch 1 outcome 0
a cancelled kill: the call'"'"'s outcome is its drop'"'"'s: yes
an interrupted kill: outcome 2, in a try: outcome 2, caught 0'

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
    { grep -E "^a (cancelled )?kill:" "$TMP/host.err"; grep -vE "^a (cancelled )?kill:" "$TMP/host.err" | head -5; } | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] emit_lib_actor_step_context: an actor a call's ask steps runs outside the call: not cut by its deadline, no interruption left for the next call, no caller info of the call; a kill whose drop the deadline or a cancel cuts ends its call with it and leaves the next call's try its own; an ordinary panic in a drop during the deadline's unwind leaves the deadline the call's"
