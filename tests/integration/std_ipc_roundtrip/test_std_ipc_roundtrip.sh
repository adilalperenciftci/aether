#!/bin/sh
# std.ipc round-trip integration test.
#
# Exercises the parent ↔ child back-channel via the three spawn
# variants (run_pipe_drain_and_wait, run_pipe + wait_pid, and
# run_capture as a negative control), then a program that cannot start,
# one that exits 127 and an explicit env (#3170). Probe.ae compiles the
# child binary in the temp directory and runs all seven cases.
#
# Skips on Windows — std.ipc is POSIX-only in v1; Windows
# parent_channel returns -1 unconditionally and the parent-side
# spawn returns "unsupported on Windows".

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

# The platform from uname, never from the environment's OS, which an MSYS2
# login shell started from another shell does not carry (check_platform_env.py).
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
        echo "  [SKIP] std_ipc_roundtrip: std.ipc is POSIX-only in v1"
        exit 0 ;;
esac

if [ ! -x "$AE" ]; then
    echo "  [SKIP] std_ipc_roundtrip: ae not built"
    exit 0
fi

cd "$ROOT" || exit 1

# The probe builds its child in the temp directory under a name of its own
# process (#2771); TMPDIR names this run's directory, which the trap removes.
TMPDIR="$(mktemp -d)"
export TMPDIR
trap 'rm -rf "$TMPDIR" || true' EXIT

if ! AETHER_HOME="$ROOT" "$AE" run "$SCRIPT_DIR/probe.ae" >"$TMPDIR/out.log" 2>&1; then
    echo "  [FAIL] std_ipc_roundtrip"
    tail -40 "$TMPDIR/out.log" | sed 's/^/    /'
    exit 1
fi

if ! grep -q "std_ipc_roundtrip: 7 passing, 0 failing" "$TMPDIR/out.log"; then
    echo "  [FAIL] std_ipc_roundtrip — not all 7 cases passed"
    tail -40 "$TMPDIR/out.log" | sed 's/^/    /'
    exit 1
fi

echo "  [PASS] std_ipc_roundtrip"
exit 0
