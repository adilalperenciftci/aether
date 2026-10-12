# The time limit the sweep runners put on each test and stage (#2758):
# tests/scripts/run_ae_test.sh, run_ae_sh_dir.sh and run_stage.sh.
#
#   . "$root/tests/lib/sweep_timeout.sh"
#   sweep_timeout_bound VAR ROOT SECONDS [KILL_AFTER]
#   $VAR command args...      # exits 124 when SECONDS pass first
#
# sweep_timeout_bound sets VAR to the words to put in front of a command:
# `timeout SECONDS` (`-k KILL_AFTER` too, when given), `gtimeout` where only
# that exists (macOS with coreutils), or nothing when neither does, so the
# command runs unbounded as before.
#
# On Windows it is never timeout(1). timeout(1) ends a command by signalling
# its process group, and a signal sent to the MSYS2 process that stands in for
# a native program makes the MSYS2 runtime walk the Windows process table by
# recorded parent pids, which Windows recycles, and signal every MSYS2
# process-group leader it finds: the CI step's own bash among them (exit code
# 2304), and a SIGTERM walk injects an exit into any native process it reaches
# (tests/lib/server_jobs.sh tells the whole story, #2479). There VAR names
# sweep_timeout_windows, which runs the command in a subshell that a native
# watchdog (tests/lib/sweep_watchdog.c, built on first use into ROOT/build)
# has put in a job object first. When the limit passes the watchdog ends the
# job, the command and everything it started, with TerminateProcess: no signal
# is sent to anything. The exit status is the command's, or 124 at the limit,
# as with timeout(1). KILL_AFTER has no meaning there, since nothing is asked
# to stop before it is ended.
#
# _SWEEP_TIMEOUT_WINDOWS is set from uname unless the caller set it: set it
# empty to take the timeout(1) branch on Windows, which is how that branch is
# tested there.

if [ -z "${_SWEEP_TIMEOUT_WINDOWS+set}" ]; then
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) _SWEEP_TIMEOUT_WINDOWS=1 ;;
        *) _SWEEP_TIMEOUT_WINDOWS= ;;
    esac
fi

# The watchdog, compiled when missing or older than its source. Workers of
# one sweep may get here at once: each compiles to a file of its own and
# renames it into place; a rename that loses to a copy already running keeps
# that copy. Prints the path, or nothing when it cannot be built (the
# compiler's output is then in ROOT/build/sweep_watchdog.log).
_sweep_timeout_watchdog() {
    _stw_src="$1/tests/lib/sweep_watchdog.c"
    _stw_out="$1/build/sweep_watchdog.exe"
    if [ ! -f "$_stw_out" ] || [ "$_stw_src" -nt "$_stw_out" ]; then
        mkdir -p "$1/build" 2>/dev/null
        _stw_tmp="$1/build/sweep_watchdog.$$.tmp.exe"
        if ${CC:-gcc} -O2 -o "$_stw_tmp" "$_stw_src" >"$_stw_tmp.log" 2>&1 ||
           cc -O2 -o "$_stw_tmp" "$_stw_src" >>"$_stw_tmp.log" 2>&1; then
            mv -f "$_stw_tmp" "$_stw_out" 2>/dev/null
        else
            mv -f "$_stw_tmp.log" "$1/build/sweep_watchdog.log" 2>/dev/null
        fi
        rm -f "$_stw_tmp" "$_stw_tmp.log"
    fi
    [ -f "$_stw_out" ] && printf '%s\n' "$_stw_out"
}

sweep_timeout_bound() {
    _stb_var="$1"
    _stb_secs="$3"
    _stb_k="${4:-}"
    if [ -n "$_SWEEP_TIMEOUT_WINDOWS" ]; then
        _SWEEP_TIMEOUT_WATCHDOG=$(_sweep_timeout_watchdog "$2")
        if [ -n "$_SWEEP_TIMEOUT_WATCHDOG" ]; then
            eval "$_stb_var=\"sweep_timeout_windows \$_stb_secs\""
            return 0
        fi
        echo "sweep_timeout: could not build tests/lib/sweep_watchdog.c (see build/sweep_watchdog.log); this runs without a time limit" >&2
        eval "$_stb_var="
        return 0
    fi
    for _stb_tool in timeout gtimeout; do
        if command -v "$_stb_tool" >/dev/null 2>&1; then
            if [ -n "$_stb_k" ]; then
                eval "$_stb_var=\"\$_stb_tool -k \$_stb_k \$_stb_secs\""
            else
                eval "$_stb_var=\"\$_stb_tool \$_stb_secs\""
            fi
            return 0
        fi
    done
    eval "$_stb_var="
}

# sweep_timeout_windows SECONDS command args...
#
# The command runs in a background subshell, which waits for the go file the
# watchdog creates once that subshell is in its job, so nothing the command
# starts can be created outside the job. The subshell stays the command's
# parent until it ends (the `exit` keeps bash from exec'ing the command in
# its place, which would end the process the watchdog waits on at once), and
# exits with the command's status, so a command ended by a signal reads as
# 128+N, as through timeout(1). The subshell's own stderr is /dev/null, and
# the command gets the real one back (fd 9): bash reports a child that a
# signal ended ("Killed", "Segmentation fault") on its stderr, and
# timeout(1) in its place said nothing, so a test's .err file gains no line.
# The explicit stdin redirection keeps this shell's stdin, which a
# background list would otherwise lose to /dev/null.
sweep_timeout_windows() {
    _stx_secs="$1"
    shift
    if [ -z "${_SWEEP_TIMEOUT_TMP:-}" ]; then
        _SWEEP_TIMEOUT_TMP="${TMPDIR:-/tmp}"
        _SWEEP_TIMEOUT_TMPW=$(cygpath -m "$_SWEEP_TIMEOUT_TMP")
    fi
    _SWEEP_TIMEOUT_SEQ=$(( ${_SWEEP_TIMEOUT_SEQ:-0} + 1 ))
    _stx_name="sweep_timeout.$$.${_SWEEP_TIMEOUT_SEQ}.go"
    _stx_go="$_SWEEP_TIMEOUT_TMP/$_stx_name"
    rm -f "$_stx_go"
    (
        exec 9>&2 2>/dev/null
        while [ ! -e "$_stx_go" ]; do sleep 0.01; done
        "$@" 2>&9 9>&-
        exit $?
    ) 0<&0 &
    _stx_cmd=$!
    _stx_winpid=
    read -r _stx_winpid < "/proc/$_stx_cmd/winpid" || :
    "$_SWEEP_TIMEOUT_WATCHDOG" "$_stx_winpid" "$_stx_secs" \
        "$_SWEEP_TIMEOUT_TMPW/$_stx_name" </dev/null &
    _stx_dog=$!
    # A watchdog that never ran (it could not start, or died before its go
    # file) would leave the command waiting forever: release it here.
    while [ ! -e "$_stx_go" ] && kill -0 "$_stx_dog" 2>/dev/null; do
        sleep 0.01
    done
    [ -e "$_stx_go" ] || : > "$_stx_go"
    # `|| ...` keeps a caller's `set -e` from leaving here before the
    # watchdog is reaped and the go file removed.
    _stx_rc=0
    wait "$_stx_cmd" || _stx_rc=$?
    _stx_dog_rc=0
    wait "$_stx_dog" || _stx_dog_rc=$?
    rm -f "$_stx_go"
    case "$_stx_dog_rc" in
        0) return "$_stx_rc" ;;
        124) return 124 ;;
        *) echo "sweep_timeout: the watchdog could not bound '$1' (exit $_stx_dog_rc); it ran without a time limit" >&2
           return "$_stx_rc" ;;
    esac
}
