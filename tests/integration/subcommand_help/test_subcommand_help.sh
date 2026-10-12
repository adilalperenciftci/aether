#!/bin/sh
# #2753: inside a project, `ae build --help` built the project: cmd_build
# skipped -h and --help as "consumed by the global pre-dispatch parse", which
# never acted on them. Most commands had the same fault in some form: run,
# check, inspect and test ran the project or its tests, init and use took
# "--help" for a name, install and upgrade went to the network, repl started,
# and examples built every example.
#
# Every command `ae help` lists, plus the update alias, is asked for -h and
# --help inside a project, with HOME pointed at an empty directory and stdin
# closed. Each has to print its own usage on stdout, exit 0, and leave the
# project and that HOME exactly as they were.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] subcommand_help: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "  [FAIL] $1"; exit 1; }

mkdir -p "$TMP/proj/src" "$TMP/proj/tests" "$TMP/proj/examples" "$TMP/home"
cat > "$TMP/proj/aether.toml" <<'EOF'
[package]
name = "proj"
version = "0.1.0"

[[bin]]
name = "main"
path = "src/main.ae"
EOF
printf 'main() {\n    println("hi")\n}\n' > "$TMP/proj/src/main.ae"
printf 'main() {\n    exit(1)\n}\n' > "$TMP/proj/tests/test_fails.ae"
printf 'main() {\n    println("example")\n}\n' > "$TMP/proj/examples/demo.ae"

# What `ae help` lists, so a command added there is checked here too.
cmds=$("$AE" help 2>/dev/null | tr -d '\r' |
       sed -n '/^Commands:/,/^$/p' | sed -n 's/^  \([a-z][a-z-]*\).*/\1/p' | sort -u)
[ -n "$cmds" ] || fail "could not read the command list from 'ae help'"
printf '%s\n' "$cmds" | grep -qx build || fail "'ae help' lists no build command: $cmds"
cmds="$cmds update"

snapshot() { (cd "$TMP" && find proj home | sort); }
before=$(snapshot)

cd "$TMP/proj" || fail "cannot enter the project"
for cmd in $cmds; do
    for flag in --help -h; do
        out=$(HOME="$TMP/home" USERPROFILE="$TMP/home" "$AE" "$cmd" "$flag" </dev/null 2>"$TMP/err")
        rc=$?
        [ "$rc" -eq 0 ] \
            || fail "'ae $cmd $flag' exited $rc: $(cat "$TMP/err") $out"
        want="Usage: ae $cmd"
        [ "$cmd" = help ] && want="Usage:"
        printf '%s\n' "$out" | grep -q "^$want" \
            || fail "'ae $cmd $flag' did not print its usage on stdout: $out"
        [ "$(snapshot)" = "$before" ] \
            || fail "'ae $cmd $flag' changed the project or HOME: $(snapshot)"
    done
done

# The options after the subcommand do not hide the request, and `--` passes
# a -h on to the program `ae run` starts instead.
out=$("$AE" build -o app --quick --help </dev/null 2>&1) \
    || fail "'ae build -o app --quick --help' failed: $out"
printf '%s\n' "$out" | grep -q "^Usage: ae build" \
    || fail "'ae build -o app --quick --help' did not print the usage: $out"
printf '%s\n' "$out" | grep -q -- "--target" \
    || fail "'ae build --help' does not list the build options: $out"
[ "$(snapshot)" = "$before" ] || fail "'ae build ... --help' built something"

cat > "$TMP/args.ae" <<'EOF'
import std.os
main() {
    println("program ran with ${os.args_count()} args")
}
EOF
out=$("$AE" run "$TMP/args.ae" -- -h </dev/null 2>&1)
printf '%s\n' "$out" | grep -q "program ran with" \
    || fail "'ae run file -- -h' did not run the program: $out"
printf '%s\n' "$out" | grep -q "Usage: ae run" \
    && fail "'ae run file -- -h' printed ae's usage as well: $out"

echo "  [PASS] subcommand_help: every command prints its usage for -h and --help and does nothing else"
