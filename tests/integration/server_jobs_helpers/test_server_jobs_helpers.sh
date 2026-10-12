#!/bin/sh
# tests/lib/server_jobs.sh ends what a shell test starts (#2479).
#
# Every shell test that starts a background program ends it through these
# helpers (check_shell_kills.py holds them to it), so they are checked here
# on their own: a running job ends and is reaped, an empty pid and a job that
# already finished are no-ops, stop_server turns to SIGKILL when SIGTERM is
# ignored (POSIX), and signal_server refuses on Windows, where a signal to a
# native program's MSYS2 stand-in also reaches unrelated processes.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
NAME=server_jobs_helpers
. "$ROOT/tests/lib/server_jobs.sh"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] $NAME: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
P=""
cleanup() {
    kill_server "$P"
    rm -rf "$tmp" || true
}
trap cleanup EXIT
fail() { echo "  [FAIL] $NAME: $1"; exit 1; }

AETHER_HOME="$ROOT" "$AE" build "$SCRIPT_DIR/sleeper.ae" -o "$tmp/sleeper" >"$tmp/build.log" 2>&1 \
    || { sed -n '1,12p' "$tmp/build.log"; fail "sleeper.ae did not build"; }

# Seconds since the epoch, for the bounds below.
now() { date +%s; }

# 1. kill_server ends a running native program and reaps it.
"$tmp/sleeper" &
P=$!
sleep 0.5
server_alive "$P" || fail "the sleeper is not a running job after it started"
t0=$(now)
kill_server "$P"
server_alive "$P" && fail "kill_server left the job running"
[ $(($(now) - t0)) -lt 15 ] || fail "kill_server took $(($(now) - t0)) s"

# 2. stop_server does the same.
"$tmp/sleeper" &
P=$!
sleep 0.5
stop_server "$P"
server_alive "$P" && fail "stop_server left the job running"

# 3. An empty pid and a job that already ended are done already.
kill_server "" || fail "kill_server of an empty pid failed"
stop_server "" || fail "stop_server of an empty pid failed"
stop_server "$P" || fail "stop_server of a reaped job failed"
P=""

if [ -n "$_SERVER_JOBS_WINDOWS" ]; then
    # 4w. No signal reaches a native program's stand-in on Windows.
    "$tmp/sleeper" &
    P=$!
    sleep 0.5
    signal_server TERM "$P" 2>/dev/null
    [ $? -eq 2 ] || fail "signal_server did not refuse on Windows"
    server_alive "$P" || fail "the refused signal_server ended the job"
    kill_server "$P"
    P=""
else
    # 4p. stop_server turns to SIGKILL for a program that ignores SIGTERM.
    sh -c 'trap "" TERM; i=0; while [ $i -lt 60 ]; do sleep 1; i=$((i + 1)); done' &
    P=$!
    sleep 0.5
    t0=$(now)
    stop_server "$P"
    server_alive "$P" && fail "stop_server left a SIGTERM-ignoring job running"
    [ $(($(now) - t0)) -lt 15 ] || fail "stop_server took $(($(now) - t0)) s"
    P=""

    # 5p. signal_server delivers the signal it is given.
    sh -c 'trap "echo got-usr1 > \"$1\"; exit 0" USR1; while :; do sleep 1; done' _ "$tmp/usr1" &
    P=$!
    sleep 0.5
    signal_server USR1 "$P" || fail "signal_server USR1 failed"
    i=0
    while [ "$i" -lt 50 ] && [ ! -s "$tmp/usr1" ]; do sleep 0.1; i=$((i + 1)); done
    grep -q got-usr1 "$tmp/usr1" 2>/dev/null || fail "signal_server USR1 did not reach the job"
    kill_server "$P"
    P=""
fi

echo "  [PASS] $NAME: kill_server, stop_server and signal_server end and reap their jobs"
exit 0
