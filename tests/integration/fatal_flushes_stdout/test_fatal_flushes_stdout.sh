#!/bin/sh
# #3435: what a program printed before a fatal error reaches its stdout.
#
# The runtime ends the process on an error it cannot return (a panic outside
# any try, a failed runtime check, a fatal std.log record, an
# out-of-memory it cannot report) with its message on stderr and abort().
# stdout is fully buffered when it is a file or a pipe, and glibc's abort()
# has flushed no stdio stream since 2.27, so the program's last lines were
# lost (emit_lib_generated_alloc's "caught:" line, on every Linux leg).
# macOS's abort() flushes, so this failed on Linux only.
#
# Each program prints two lines and then fails; its stdout goes to a file,
# which must hold both lines.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
NAME=fatal_flushes_stdout
[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0

# check <label> <main body>
check() {
    printf 'import std.log\n\nmain() {\n    println("first line")\n    println("second line")\n%s\n}\n' "$2" > "$T/p.ae"
    if ! "$AE" build "$T/p.ae" -o "$T/p" >"$T/build.log" 2>&1; then
        echo "    FAIL: $1: build failed"; sed 's/^/      /' "$T/build.log" | head -8
        fails=$((fails + 1)); return
    fi
    AETHER_STACK_TRACE=0 "$T/p" > "$T/out.txt" 2> "$T/err.txt"
    rc=$?
    got=$(tr -d '\r' < "$T/out.txt" | tr '\n' '|')
    if [ "$rc" -ne 0 ] && [ "$got" = "first line|second line|" ] && [ -s "$T/err.txt" ]; then
        echo "    ok: $1: both lines reached the file, then the error (exit $rc)"
    else
        echo "    FAIL: $1: exit $rc, stdout [$got], stderr [$(head -2 "$T/err.txt" | tr '\n' '|')]"
        fails=$((fails + 1))
    fi
}

check "a panic outside any try" '    panic("the end")'
check "a fatal log record" '    log.write(log.LOG_LEVEL_FATAL, "the end")'

[ "$fails" = 0 ] || { echo "  [FAIL] $NAME: $fails case(s)"; exit 1; }
echo "  [PASS] $NAME: a panic and a fatal log record leave the program's lines on its stdout"
