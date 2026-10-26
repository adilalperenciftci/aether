#!/bin/sh
# Regression (#3178): a child spawn_sandboxed starts may run threads, and
# std.sandbox can grant it new processes.
#
# The kernel fence spawn_sandboxed installs refused every clone, a thread's
# too, so a child that starts a thread failed: an Aether program with
# actors (its scheduler's workers are threads), Python with threads, a JVM.
# And the grant that lifts the fence, `fork`, was spelt nowhere in
# std.sandbox, the one place grant names are spelt, so only a hand-built
# list could hold it. Now a thread passes the fence, and grant_fork() lets
# the child start processes.
#
# The child is an Aether program (the launcher itself, started again) held
# to grants that allow it everything but new processes, unless the case adds
# grant_fork(). Its actors must run in every case; `os.exec` (a new process)
# only with grant_fork().

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

case "$(uname -s 2>/dev/null)" in
    Linux) ;;
    *)
        echo "  [SKIP] sandbox_fork_grant: the clone fence is Linux only"
        exit 0 ;;
esac
if [ ! -x "$AE" ]; then
    echo "  [SKIP] sandbox_fork_grant: ae not built"
    exit 0
fi
if [ ! -f "$ROOT/build/libaether_sandbox.so" ]; then
    echo "  [SKIP] sandbox_fork_grant: build/libaether_sandbox.so not built"
    exit 0
fi

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export AETHER_CACHE_DIR="$TMP/cache"
. "$ROOT/tests/lib/sweep_timeout.sh"
sweep_timeout_bound TO "$ROOT" 60

cat > "$TMP/launch.ae" <<'EOF'
import std.os
import std.sandbox
import std.string

message Ping {}

actor Echo {
    receive {
        Ping -> {
            println("child: an actor ran")
        }
    }
}

// The child: actors, then a process.
child() {
    e = spawn(Echo())
    e ! Ping {}
    wait_for_idle()
    out, err = os.exec("echo started")
    if err == "" {
        println("child: a process ${string.trim(out)}")
    } else {
        println("child: no process")
    }
}

// launch <plain|fork>: start this program again, held to grants that allow
// it everything but new processes, unless `fork` adds grant_fork().
main() {
    if os.args_get(1) == "child" {
        child()
        return
    }
    with_fork = os.args_get(1) == "fork"
    worker = sandbox.new("worker") {
        grant_fs_read("/*")
        grant_fs_write("/*")
        grant_exec("*")
        grant_env("*")
        grant_native("*")
    }
    defer sandbox.free(worker)
    forker = sandbox.new("forker") {
        grant_fs_read("/*")
        grant_fs_write("/*")
        grant_exec("*")
        grant_env("*")
        grant_native("*")
        grant_fork()
    }
    defer sandbox.free(forker)
    grants = if with_fork { forker } else { worker }
    rc = spawn_sandboxed(grants, os.argv0(), "child")
    println("rc=${rc}")
}
EOF
if ! (cd "$TMP" && AETHER_HOME="$ROOT" "$AE" build launch.ae -o launch) > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] sandbox_fork_grant: the launcher does not build:"
    sed 's/^/        /' "$TMP/build.log" | head -12
    exit 1
fi

fail=0

# check LABEL MODE WANT...: run the launcher in MODE; each WANT is a line
# its output must hold.
check() {
    label="$1"
    mode="$2"
    shift 2
    out="$(cd "$TMP" && AETHER_HOME="$ROOT" $TO "$TMP/launch" "$mode" 2>&1)"
    for want in "$@"; do
        if ! printf '%s\n' "$out" | grep -qxF -- "$want"; then
            echo "  [FAIL] $label: no line \"$want\" in:"
            printf '%s\n' "$out" | sed 's/^/        /' | head -12
            fail=1
            return
        fi
    done
    echo "  [PASS] $label"
}

check "without grant_fork: the child's actors run, and it starts no process" plain \
    "child: an actor ran" "child: no process" "rc=0"
check "with grant_fork: the child starts a process too" fork \
    "child: an actor ran" "child: a process started" "rc=0"

exit $fail
