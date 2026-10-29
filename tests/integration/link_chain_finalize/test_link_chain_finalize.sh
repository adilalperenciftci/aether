#!/bin/sh
# Regression (#3394): a chain of linked actors ends in a stack depth that
# does not grow with the chain.
#
# A death is told to the actors linked to it (aether_watch_notify), and a
# link that does not trap exits ends the other actor in turn (link_effect).
# Where a death is finalized as soon as it is seen (the cooperative
# scheduler, and the threaded one while it is not running), that end ran
# inside the previous actor's finalize: kill the first of 8000 linked actors
# and the stack held a few frames per actor, which overflowed a 256 KiB
# thread (wasm, an ESP32 task or a host's thread have no more). The deaths
# are told one after the other now, through a queue of the thread's.
#
# chain.c builds the chain and kills its head on a small-stack thread
# (stack.c); it is built against libaether (the threaded scheduler, stopped
# before the kill) and against the cooperative runtime
# (runtime/coop_runtime_sources.txt), and in each every actor must have
# ended.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
CC="${CC:-cc}"
N=8000
STACK_KB=256

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] link_chain_finalize: $AE not built"; exit 0; }
[ -f "$ROOT/build/libaether.a" ] || { echo "  [SKIP] link_chain_finalize: build/libaether.a not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT

# The include and link flags of an embedding build; the program has its
# own main.
FLAGS="$(AETHER_HOME="$ROOT" "$AE" cflags | tr -d '\r' | sed 's/-laether_main//')"
INCS="$(printf '%s\n' "$FLAGS" | tr ' ' '\n' | awk '
    /^-I/ || /^-f/ { print; next }
    /^-idirafter$/ { getline d; print "-idirafter " d; next }
    /^-idirafter/ { print }' | tr '\n' ' ')"

fail=0

run_chain() {
    label=$1
    exe=$2
    out="$TMP/$label.out"
    "$exe" "$N" "$STACK_KB" > "$out" 2>&1
    rc=$?
    if [ $rc -ne 0 ] || ! grep -q "^ended $N of $N" "$out"; then
        echo "  [FAIL] link_chain_finalize: $label: killing the head of $N linked actors on a ${STACK_KB} KiB stack (exit $rc)"
        head -5 "$out" | sed 's/^/        /'
        fail=1
    else
        echo "  [PASS] link_chain_finalize: $label: $N linked actors ended on a ${STACK_KB} KiB stack"
    fi
}

# The threaded scheduler, not started.
if ! $CC -O2 $INCS -c "$SCRIPT_DIR/chain.c" -o "$TMP/chain_mc.o" > "$TMP/mc.log" 2>&1 ||
   ! $CC -O2 -c "$SCRIPT_DIR/stack.c" -o "$TMP/stack.o" >> "$TMP/mc.log" 2>&1 ||
   ! $CC "$TMP/chain_mc.o" "$TMP/stack.o" -o "$TMP/chain_mc" $FLAGS >> "$TMP/mc.log" 2>&1; then
    echo "  [FAIL] link_chain_finalize: could not build the threaded program"
    head -10 "$TMP/mc.log" | sed 's/^/        /'
    exit 1
fi
run_chain threaded "$TMP/chain_mc"

# The cooperative runtime, as the wasm and ESP32 builds link it.
COOP="-DAETHER_NO_THREADING -DAETHER_NO_FILESYSTEM -DAETHER_NO_NETWORKING"
mkdir -p "$TMP/coop"
sed -e '/^#/d' -e '/^[[:space:]]*$/d' "$ROOT/runtime/coop_runtime_sources.txt" | tr -d '\r' |
    while read -r src; do
        if ! $CC -O1 $COOP $INCS -c "$ROOT/$src" -o "$TMP/coop/$(echo "$src" | tr / _).o" >> "$TMP/coop.log" 2>&1; then
            echo "$src" >> "$TMP/coop.failed"
        fi
    done
if [ -s "$TMP/coop.failed" ] ||
   ! $CC -O2 $COOP $INCS -c "$SCRIPT_DIR/chain.c" -o "$TMP/chain_coop.o" >> "$TMP/coop.log" 2>&1 ||
   ! ar rcs "$TMP/libcoop.a" "$TMP"/coop/*.o >> "$TMP/coop.log" 2>&1 ||
   ! $CC "$TMP/chain_coop.o" "$TMP/stack.o" -o "$TMP/chain_coop" "$TMP/libcoop.a" -pthread -lm >> "$TMP/coop.log" 2>&1; then
    echo "  [FAIL] link_chain_finalize: could not build the cooperative program"
    [ -s "$TMP/coop.failed" ] && sed 's/^/        /' "$TMP/coop.failed"
    grep -m 10 -E 'error|undefined' "$TMP/coop.log" | sed 's/^/        /'
    exit 1
fi
run_chain cooperative "$TMP/chain_coop"

exit $fail
