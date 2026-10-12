#!/bin/sh
# #2758: a hung test under the sweep's time limit fails as a timeout (124)
# and takes nothing else with it. The limit is tests/lib/sweep_timeout.sh,
# which tests/scripts/run_ae_test.sh, run_ae_sh_dir.sh and run_stage.sh use.
#
# On Windows the limit was timeout(1), which ends a hung test by signalling
# it. A signal sent to the MSYS2 process standing in for a native program
# makes the MSYS2 runtime signal every MSYS2 process-group leader it finds
# through recorded (and recycled) parent pids, and on the CI runner that
# reached the step's own bash: the job died with exit code 2304 (#2479). The
# limit there is now a job object ended by TerminateJobObject, which signals
# nothing.
#
# A deliberately hung native program runs under a 3 s limit twice over, in
# the foreground of a bash that traps SIGTERM and in the background beside
# it, inside a "sweep" shell that reports what it saw. The sweep shell has to
# survive and see 124, both copies of the program have to be gone, and on
# Windows the trap must not have run, since nothing may be signalled there.
# Elsewhere the limit is timeout(1), whose SIGTERM is exactly what the trap
# sees. The program gives up by itself after 60 s, so a limit that failed
# cannot leave it behind for long.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "  [FAIL] $1"; exit 1; }

case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) windows=1 ;;
    *) windows= ;;
esac
if [ -z "$windows" ] && ! command -v timeout >/dev/null 2>&1 &&
   ! command -v gtimeout >/dev/null 2>&1; then
    echo "  [SKIP] sweep_timeout: no timeout(1) here, so the sweep runs unbounded"
    exit 0
fi

cat > "$TMP/hang.c" <<'EOF'
#include <stdio.h>
#ifdef _WIN32
#include <windows.h>
#define SELF ((unsigned long)GetCurrentProcessId())
#define NAP() Sleep(1000)
#else
#include <unistd.h>
#define SELF ((unsigned long)getpid())
#define NAP() sleep(1)
#endif
int main(int argc, char** argv) {
    FILE* f = argc > 1 ? fopen(argv[1], "a") : NULL;
    if (f) { fprintf(f, "%lu\n", SELF); fclose(f); }
    for (int i = 0; i < 60; i++) NAP();
    return 0;
}
EOF
# A name of its own, so on Windows the check below cannot mistake another
# program that took over the pid for this one.
hang="$TMP/sweep_hang_$$"
${CC:-cc} -o "$hang" "$TMP/hang.c" 2>"$TMP/cc.log" \
    || { cat "$TMP/cc.log"; fail "could not compile the hung program"; }
[ -f "$hang.exe" ] && hang="$hang.exe"

# Each copy writes its pid to a file of its own: two appends to one file can
# land on the same offset on Windows, and a pid would be lost.
cat > "$TMP/hung_test.sh" <<'EOF'
trap 'echo "SIGTERM reached the test"' TERM
"$1" "$2.background" &
"$1" "$2.foreground"
EOF

cat > "$TMP/sweep.sh" <<'EOF'
. "$1/tests/lib/sweep_timeout.sh"
sweep_timeout_bound TO "$1" 3
$TO bash "$2" "$3" "$4"
echo "rc=$?"
echo "sweep shell still running"
EOF

start=$(date +%s)
out=$(bash "$TMP/sweep.sh" "$ROOT" "$TMP/hung_test.sh" "$hang" "$TMP/pid" 2>&1)
sweep_rc=$?
elapsed=$(( $(date +%s) - start ))

[ "$sweep_rc" -eq 0 ] || fail "the sweep shell exited $sweep_rc: $out"
printf '%s\n' "$out" | grep -q "sweep shell still running" \
    || fail "the sweep shell did not get past the hung test: $out"
printf '%s\n' "$out" | grep -q "^rc=124$" \
    || fail "the hung test did not end as a timeout (124): $out"
[ "$elapsed" -lt 30 ] \
    || fail "the 3 s limit took ${elapsed}s: the program ran until it gave up by itself"

cat "$TMP/pid.background" "$TMP/pid.foreground" 2>/dev/null | tr -d '\r' > "$TMP/pids.txt"
npids=$(grep -c . "$TMP/pids.txt")
[ "$npids" = 2 ] || fail "expected both copies of the program to start, $npids did"
for p in $(cat "$TMP/pids.txt"); do
    if [ -n "$windows" ]; then
        img=$(basename "$hang")
        "$(cygpath -S)/tasklist.exe" //NH //FI "PID eq $p" //FI "IMAGENAME eq $img" 2>/dev/null \
            | grep -qi "$img" && fail "the hung program (pid $p) outlived the limit"
    else
        kill -0 "$p" 2>/dev/null && fail "the hung program (pid $p) outlived the limit"
    fi
done

if [ -n "$windows" ]; then
    printf '%s\n' "$out" | grep -q "SIGTERM reached the test" \
        && fail "the limit signalled the test on Windows, where a signal can reach unrelated processes (#2758)"
    echo "  [PASS] sweep_timeout: a hung test ends as 124 through a job object, with no signal, and the sweep shell survives"
else
    printf '%s\n' "$out" | grep -q "SIGTERM reached the test" \
        || fail "timeout(1)'s SIGTERM never reached the test: $out"
    echo "  [PASS] sweep_timeout: a hung test ends as 124 through timeout(1), and the sweep shell survives"
fi
