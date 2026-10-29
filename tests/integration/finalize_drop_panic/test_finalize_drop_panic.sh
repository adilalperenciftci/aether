#!/bin/sh
# Regression (#3401): a panic in the release of a message an ending actor
# leaves undelivered does not stop the actor's end.
#
# A dropped message's release is the program's code for a field of an
# owned type (its drop function, #3142). Where a death is finalized as soon
# as it is seen (the cooperative scheduler, and the threaded one once
# stopped), a panic there left the finalize: the messages after it were not
# released, and the actor's watchers and links were never told. Each drop
# now runs in a frame of its own; a panic in one is reported through the
# death hook, as the step barrier reports a panic in a release after a
# handler, and the end goes on. A death hook that panics when it is told of
# that panic left the finalize halfway in turn, the rest of the drain, its
# count and the notices undone (#3417); it runs in a frame of its own too.
#
# drop.c is built against libaether (the threaded scheduler, stopped
# before the kill) and against the cooperative runtime
# (runtime/coop_runtime_sources.txt), and must print PASS from both.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
CC="${CC:-cc}"
NAME=finalize_drop_panic

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] $NAME: $AE not built"; exit 0; }
[ -f "$ROOT/build/libaether.a" ] || { echo "  [SKIP] $NAME: build/libaether.a not built"; exit 0; }

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

run_drop() {
    label=$1
    exe=$2
    out="$TMP/$label.out"
    "$exe" > "$out" 2>&1
    rc=$?
    if [ $rc -ne 0 ] || ! grep -q "^PASS" "$out"; then
        echo "  [FAIL] $NAME: $label (exit $rc)"
        grep -v "scheduler is not running" "$out" | head -6 | sed 's/^/        /'
        fail=1
    else
        echo "  [PASS] $NAME: $label: the end goes on past a panicking drop, and past a death hook that panics on it"
    fi
}

# The threaded scheduler, stopped.
if ! $CC -O2 $INCS -c "$SCRIPT_DIR/drop.c" -o "$TMP/drop_mc.o" > "$TMP/mc.log" 2>&1 ||
   ! $CC "$TMP/drop_mc.o" -o "$TMP/drop_mc" $FLAGS >> "$TMP/mc.log" 2>&1; then
    echo "  [FAIL] $NAME: could not build the threaded program"
    head -10 "$TMP/mc.log" | sed 's/^/        /'
    exit 1
fi
run_drop threaded "$TMP/drop_mc"

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
   ! $CC -O2 $COOP $INCS -c "$SCRIPT_DIR/drop.c" -o "$TMP/drop_coop.o" >> "$TMP/coop.log" 2>&1 ||
   ! ar rcs "$TMP/libcoop.a" "$TMP"/coop/*.o >> "$TMP/coop.log" 2>&1 ||
   ! $CC "$TMP/drop_coop.o" -o "$TMP/drop_coop" "$TMP/libcoop.a" -pthread -lm >> "$TMP/coop.log" 2>&1; then
    echo "  [FAIL] $NAME: could not build the cooperative program"
    [ -s "$TMP/coop.failed" ] && sed 's/^/        /' "$TMP/coop.failed"
    grep -m 10 -E 'error|undefined' "$TMP/coop.log" | sed 's/^/        /'
    exit 1
fi
run_drop cooperative "$TMP/drop_coop"

exit $fail
