#!/bin/sh
# Regression (#2797 follow-up): a string a closure stores into an outer
# `ptr` local reaches C as its characters, and they outlive the closure.
#
# The store handed the `ptr` cell the closure's environment copy of the
# string as it stood: an AetherString even for a plain string, so C read
# its header (de c0 57 ae) where the scope's own `z = t` gives it the
# characters, and it was freed with the environment. The cell now takes a
# string of its own, kept in a second slot until the next string store or
# the cell's last release, and holds its characters. The probe stores a
# heap string, a destructured one and a plain one through closures (two
# released by `run` before C reads the pointer), reuses the freed memory,
# and checks the bytes C sees against the scope's own store and that 50
# rounds leave no heap behind. It must print "OK" and exit 0. The probe
# also stores strings into a `ptr` module var, which must build without
# a C warning (#2811).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] closure_ptr_cell_c_string: toolchain not built"
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cd "$SCRIPT_DIR" || exit 1

build_log="$tmpdir/build.log"
if ! "$AE" build probe.ae -o "$tmpdir/probe" >"$build_log" 2>&1; then
    echo "  [FAIL] closure_ptr_cell_c_string: ae build failed"
    sed 's/^/    /' "$build_log" | head -30
    exit 1
fi

# #2811: a string stored into the `ptr` module var is cast, not warned about.
if grep -q "discards 'const'" "$build_log"; then
    echo "  [FAIL] closure_ptr_cell_c_string: the C build warned on a ptr store"
    grep -A2 "discards 'const'" "$build_log" | sed 's/^/    /' | head -10
    exit 1
fi

run_log="$tmpdir/run.log"
"$tmpdir/probe" >"$run_log" 2>&1
rc=$?

if [ $rc -ne 0 ]; then
    echo "  [FAIL] closure_ptr_cell_c_string: probe exited $rc (expect 0)"
    sed 's/^/    /' "$run_log" | head -30
    exit 1
fi

if ! tr -d '\r' < "$run_log" | grep -q "^OK$"; then
    echo "  [FAIL] closure_ptr_cell_c_string: probe did not print 'OK'"
    sed 's/^/    /' "$run_log" | head -10
    exit 1
fi

echo "  [PASS] closure_ptr_cell_c_string: the C string outlives the closure"
exit 0
