#!/bin/sh
# Regression (#3120): the runtime structs a program and libaether share have
# one layout with and without AETHER_NO_THREADING.
#
# A cooperative libaether is built with -DAETHER_NO_THREADING and a program
# built against it by `ae` is not. On Windows the no-threads branch of
# aether_thread.h fell to the bare-metal `int` thread types while the
# threaded one has the Win32-shaped ones, so every ActorBase field after
# `thread` sat 8 bytes apart in the two, and a cooperative program died at
# exit freeing `spsc_queue` from the wrong offset. layout_probe.c prints the
# sizes and offsets of those structs; built both ways, the two must agree.
# On Linux and macOS both ways include <pthread.h>, so the Windows legs are
# the ones this guards.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CC="${CC:-cc}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

INC="-I$ROOT/runtime -I$ROOT/runtime/scheduler -I$ROOT/runtime/actors -I$ROOT/runtime/utils -I$ROOT/runtime/memory -I$ROOT/runtime/config -I$ROOT/std"

# $1 = name, $2 = extra flag
probe() {
    if ! $CC -O2 $INC $2 "$SCRIPT_DIR/layout_probe.c" -o "$TMPDIR/$1" >"$TMPDIR/$1.build" 2>&1; then
        echo "  [FAIL] thread_types_layout: the probe did not build ($1)"
        sed 's/^/        /' "$TMPDIR/$1.build" | head -8
        exit 1
    fi
    "$TMPDIR/$1" >"$TMPDIR/$1.layout"
}

probe threads ""
probe coop "-DAETHER_NO_THREADING"

if ! cmp -s "$TMPDIR/threads.layout" "$TMPDIR/coop.layout"; then
    echo "  [FAIL] thread_types_layout: layouts differ (threads | AETHER_NO_THREADING):"
    paste "$TMPDIR/threads.layout" "$TMPDIR/coop.layout" | awk -F'\t' '$1 != $2' | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] thread_types_layout: shared runtime structs agree with and without AETHER_NO_THREADING"
