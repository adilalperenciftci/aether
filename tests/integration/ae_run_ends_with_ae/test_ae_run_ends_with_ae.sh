#!/bin/sh
# Ending `ae run` ends the program it launched (#2479).
#
# `ae run` builds, then spawns the program and waits for it. On POSIX it
# relays SIGTERM / SIGINT / SIGHUP to the program (ae_run_signal_forwarding
# covers that). On Windows there is no signal to relay, and a program whose
# ae was ended by TerminateProcess (a supervisor, a Ctrl-C handler, the test
# helpers in tests/lib/server_jobs.sh) kept running, holding its port, so
# the next run of the same test could not bind. ae now keeps the program in
# a job object that kills it when ae's handle to the job goes away.
#
# The program writes its own pid; the test ends ae the way the suites end a
# server and then requires that pid to be gone.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
NAME=ae_run_ends_with_ae
. "$ROOT/tests/lib/server_jobs.sh"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] $NAME: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
AE_PID=""
cleanup() {
    stop_server "$AE_PID"
    rm -rf "$tmp" || true
}
trap cleanup EXIT

# 0 while the program with OS pid $1 runs. On Windows that pid is a Windows
# one, which the MSYS2 shell's own `kill -0` does not know.
program_running() {
    if [ -n "$_SERVER_JOBS_WINDOWS" ]; then
        "$(cygpath -S)/tasklist.exe" //FI "PID eq $1" //NH 2>/dev/null | grep -q " $1 "
    else
        kill -0 "$1" 2>/dev/null
    fi
}

AE_RUN_PID_FILE="$tmp/pid" AETHER_HOME="$ROOT" "$AE" run "$SCRIPT_DIR/longrun.ae" \
    >"$tmp/out.log" 2>&1 &
AE_PID=$!

# The build comes first; then the program writes its pid.
prog=""
i=0
while [ "$i" -lt 240 ]; do
    if [ -s "$tmp/pid" ]; then
        prog="$(tr -d '\r\n' < "$tmp/pid")"
        [ -n "$prog" ] && break
    fi
    server_alive "$AE_PID" || break
    sleep 0.5
    i=$((i + 1))
done
if [ -z "$prog" ]; then
    echo "  [FAIL] $NAME: the program never wrote its pid"
    sed -n '1,12p' "$tmp/out.log" | sed 's/^/        /'
    exit 1
fi
if ! program_running "$prog"; then
    echo "  [FAIL] $NAME: pid $prog is not running before ae is ended"
    exit 1
fi

stop_server "$AE_PID"
AE_PID=""

i=0
while [ "$i" -lt 50 ] && program_running "$prog"; do
    sleep 0.1
    i=$((i + 1))
done
if program_running "$prog"; then
    echo "  [FAIL] $NAME: the program (pid $prog) outlived the ae run that launched it"
    exit 1
fi
echo "  [PASS] $NAME: ending ae run ended the program it launched"
exit 0
