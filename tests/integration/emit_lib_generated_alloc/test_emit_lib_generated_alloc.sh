#!/bin/sh
# #3377: every allocation the generated code makes is checked.
#
# The helpers the C codegen emits (a captured variable's cell, ref, lazy,
# a closure's environment and box, heap.new) used malloc's result
# unchecked: out of memory, the program dereferenced NULL, a crash with no
# message, inside a library call or not. They now go through one checked
# allocation: inside a library call the call ends with AETHER_OUT_OF_MEMORY,
# elsewhere it is a panic naming what ran out (caught by a try, or the
# program stops with it). The program's own malloc still returns NULL, and
# ends a library call when it returns. The runtime's test hook fails each
# kind once.
#
# Fixtures, not tests: kinds.ae is a library and outside.ae a program; the
# driver builds both.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
CC="${CC:-cc}"
export AETHER_HOME="$ROOT"
export AETHER_STACK_TRACE=0

[ -x "$AE" ] || { echo "  [SKIP] emit_lib_generated_alloc: $AE not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT
oom='outcome 5 "the call ran out of memory"'
want="cell 0 $oom
ref 0 $oom
lazy 0 $oom
env 0 $oom
box 0 $oom
heap 0 $oom
malloc 0 $oom
plain 6 outcome 0 \"\""

if ! "$AETHERC" --emit=lib --with=extern "$SCRIPT_DIR/kinds.ae" "$TMP/kinds.c" > "$TMP/kinds.log" 2>&1; then
    echo "  [FAIL] emit_lib_generated_alloc: aetherc --emit=lib failed"
    tail -5 "$TMP/kinds.log" | sed 's/^/        /'
    exit 1
fi
# shellcheck disable=SC2046
if ! "$CC" -O1 -I"$ROOT/include" -I"$ROOT/runtime" $("$AE" cflags --cflags) \
        "$TMP/kinds.c" "$SCRIPT_DIR/host.c" -o "$TMP/host" \
        $("$AE" cflags --libs) > "$TMP/cc.log" 2>&1; then
    echo "  [FAIL] emit_lib_generated_alloc: the host did not build"
    head -10 "$TMP/cc.log" | sed 's/^/        /'
    exit 1
fi
got="$("$TMP/host" 2>"$TMP/host.err" | tr -d '\r')"
if [ "$got" != "$want" ]; then
    echo "  [FAIL] emit_lib_generated_alloc: library calls:"
    echo "      got:"; printf '%s\n' "$got" | sed 's/^/        /'
    echo "      want:"; printf '%s\n' "$want" | sed 's/^/        /'
    head -5 "$TMP/host.err" | sed 's/^/        /'
    exit 1
fi

if ! "$AE" build "$SCRIPT_DIR/outside.ae" -o "$TMP/outside" > "$TMP/outside_build.log" 2>&1; then
    echo "  [FAIL] emit_lib_generated_alloc: ae build outside.ae failed"
    tail -5 "$TMP/outside_build.log" | sed 's/^/        /'
    exit 1
fi
"$TMP/outside" > "$TMP/outside.out" 2> "$TMP/outside.err"
rc=$?
out="$(tr -d '\r' < "$TMP/outside.out")"
err="$(tr -d '\r' < "$TMP/outside.err")"
if [ "$out" != "caught: out of memory in heap.new" ] || [ $rc -eq 0 ] ||
   ! printf '%s\n' "$err" | grep -q "out of memory in heap.new"; then
    echo "  [FAIL] emit_lib_generated_alloc: outside a library call (exit $rc):"
    printf '%s\n' "$out" "$err" | head -8 | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] emit_lib_generated_alloc: a failed cell, ref, lazy, closure environment, closure box or heap.new allocation ends a library call with AETHER_OUT_OF_MEMORY, and outside one is a panic naming it; the program's own malloc still returns NULL"
