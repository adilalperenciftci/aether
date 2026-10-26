#!/bin/sh
# `make test-ubsan` (#2488): the C unit tests and the `make test-ae` sweep,
# with the toolchain, libaether and every program they build compiled under
# UndefinedBehaviorSanitizer. Run from the repository root.
#
#   MAKE=make NPROC=4 BASE_CC=gcc sh tests/scripts/ubsan_sweep.sh
#
# Every compile and link goes through the sanitizing compiler: build/ubsan/bin
# holds a `gcc` and a `cc` that run the real ones with the UBSan flags, put
# first on PATH and named by absolute path in CC. That reaches what the
# Makefile compiles, what `ae build` compiles (it reads CC), the shell tests
# that run "$CC" and the ones that run gcc or cc by name, which a CFLAGS
# setting would not: an instrumented libaether.a does not even link into a
# program built without the UBSan runtime. CC names the wrapper by its path,
# not as "gcc", so the build-flags digest and ae's cache key both see another
# compiler, and an instrumented object or program is never mixed with a plain
# one.
#
# A report stops the program (-fno-sanitize-recover), so the test that ran it
# fails, and is written to build/ubsan/reports/report.<program>.<pid>
# (UBSAN_OPTIONS log_path), where a test that expects its program to fail, or
# compares its stderr, cannot hide it. The run fails on any report, and lists
# them grouped by source location (also into $GITHUB_STEP_SUMMARY in CI).
#
# Before the tests, two checks that the configuration took: build/libaether.a
# must call the UBSan handlers, and tests/ubsan/canary.ae, built by ae and
# run, must be stopped by its undefined shift with a report. Without them a
# run whose flags were lost would read as a clean corpus.
#
# Needs a C compiler with a UBSan runtime: gcc's libubsan or clang's
# compiler-rt (Linux, macOS). MinGW has none; there it stops and says so.
set -u

root=$(pwd)
dir="$root/build/ubsan"
bin="$dir/bin"
reports="$dir/reports"
make_cmd=${MAKE:-make}
nproc=${NPROC:-2}
base_cc=${BASE_CC:-gcc}
flags="-fsanitize=undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"

rm -rf "$bin" "$reports" "$dir/canary"
mkdir -p "$bin" "$reports" "$dir/canary" || exit 1

# PATH without the wrapper directory, so a wrapper never resolves to itself.
plain_path=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -x -F "$bin" | paste -s -d: -)
for name in gcc cc; do
    real=$(PATH=$plain_path command -v "$name" 2>/dev/null) || continue
    case "$real" in /*) ;; *) continue ;; esac
    printf '#!/bin/sh\n# %s under UBSan, written by tests/scripts/ubsan_sweep.sh (#2488).\nexec "%s" %s "$@"\n' \
        "$name" "$real" "$flags" > "$bin/$name"
    chmod +x "$bin/$name"
done
case "$base_cc" in gcc|cc) ;; *) base_cc=cc ;; esac
if [ ! -x "$bin/$base_cc" ]; then
    echo "test-ubsan: no $base_cc on PATH to wrap" >&2
    exit 1
fi
CC="$bin/$base_cc"
PATH="$bin:$PATH"
UBSAN_OPTIONS="print_stacktrace=1:report_error_type=1:log_exe_name=1:log_path=$reports/report"
export CC PATH UBSAN_OPTIONS

printf 'int main(void) { return 0; }\n' > "$dir/probe.c"
if ! "$CC" "$dir/probe.c" -o "$dir/probe" > "$dir/probe.log" 2>&1; then
    echo "test-ubsan: $CC cannot link a program with -fsanitize=undefined here" >&2
    echo "  (no UBSan runtime: MinGW has none; run it on Linux or macOS)" >&2
    sed 's/^/  | /' "$dir/probe.log" >&2
    exit 1
fi

echo "== test-ubsan: the toolchain, built with $flags"
"$make_cmd" -j"$nproc" compiler ae stdlib CC="$CC" || exit 1

if ! nm "$root/build/libaether.a" 2>/dev/null | grep -q '__ubsan_handle_'; then
    echo "test-ubsan: build/libaether.a calls no UBSan handler: the flags did not reach the toolchain" >&2
    exit 1
fi
canary="$dir/canary/canary"
if ! "$root/build/ae" build tests/ubsan/canary.ae --extra tests/ubsan/canary.c -o "$canary" \
        > "$dir/canary/build.log" 2>&1; then
    echo "test-ubsan: the canary did not build" >&2
    sed 's/^/  | /' "$dir/canary/build.log" >&2
    exit 1
fi
UBSAN_OPTIONS="print_stacktrace=1:log_exe_name=1:log_path=$dir/canary/report" \
    "$canary" > "$dir/canary/run.out" 2>&1
canary_rc=$?
if [ "$canary_rc" -eq 0 ] || ! grep -q 'shift exponent 32' "$dir"/canary/report.* 2>/dev/null; then
    echo "test-ubsan: the canary's undefined shift was not stopped and reported (exit $canary_rc):" >&2
    echo "  a program ae builds here is not instrumented, so a clean corpus would mean nothing" >&2
    exit 1
fi
echo "  [PASS] libaether.a is instrumented, and the canary was stopped with a report"

status=0
echo "== test-ubsan: C unit tests"
"$make_cmd" -j"$nproc" test CC="$CC" || status=1
echo "== test-ubsan: the .ae corpus (make test-ae)"
"$make_cmd" test-ae CC="$CC" NPROC="$nproc" || status=1

# The reports, grouped by the source location of the first line of each.
n=$(ls "$reports" | wc -l | tr -d ' ')
{
    echo "## The C unit tests and the .ae corpus under UBSan (#2488)"
    echo
    echo "$n report file(s), one per program run that hit undefined behaviour."
    if [ "$n" -gt 0 ]; then
        echo
        echo "| programs | where | what | programs, up to 4 |"
        echo "|---|---|---|---|"
        for f in "$reports"/report.*; do
            exe=${f#"$reports"/report.}
            exe=${exe%.*}
            grep 'runtime error:' "$f" | head -1 | while IFS= read -r line; do
                printf '%s\t%s\n' "$exe" "$line"
            done
        done | awk -F'\t' -v root="$root/" '{
                loc = $2; sub(/: runtime error:.*/, "", loc)
                if (index(loc, root) == 1) loc = substr(loc, length(root) + 1)
                msg = $2; sub(/^.*: runtime error: /, "", msg); gsub(/\|/, "/", msg)
                if (!((loc, $1) in seen)) {
                    seen[loc, $1] = 1; c[loc]++
                    if (c[loc] <= 4) ex[loc] = ex[loc] " " $1
                }
                if (!(loc in first)) first[loc] = msg
            }
            END { for (l in c) printf "| %d | %s | %s |%s |\n", c[l], l, first[l], ex[l] }' |
            sort -t'|' -k2,2nr
    fi
} > "$dir/summary.md"
cat "$dir/summary.md"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$dir/summary.md" >> "$GITHUB_STEP_SUMMARY"
if [ "$n" -gt 0 ]; then
    for f in $(ls "$reports"/report.* | head -20); do
        echo "=== $f"
        head -30 "$f"
    done
    echo "test-ubsan: $n program run(s) hit undefined behaviour; the reports are in build/ubsan/reports" >&2
    status=1
fi
exit "$status"
