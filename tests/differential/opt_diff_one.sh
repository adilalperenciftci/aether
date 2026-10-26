#!/bin/sh
# Build one .ae program at -O2 (`ae build`) and at -O0 (`ae build --quick`),
# run both, and record whether their stdout and exit code agree (#2488).
#
#   opt_diff_one.sh <test.ae> <tmpdir> <repo-root>
#
# Invoked once per program, in parallel, by run_opt_diff.sh, which tallies the
# marker files this leaves in <tmpdir>/res:
#
#   SAME_<name>    stdout and exit code agree
#   DIFF_<name>    they do not; <name>.why says how
#   CARVED_<name>  exit codes agree, stdout not compared (opt_diff_carveouts.txt)
#   FAIL_<name>    a build failed or timed out; <name>.why has the log
#
# Built the way the `make test-ae` sweep builds it (run_ae_test.sh): from
# inside its own directory when a lib/ sits beside it, and run from the
# repository root. Both binaries run from the same path, one after the other,
# so a program that prints argv[0] or its own location agrees with itself.
set -u

# cmp comes from diffutils, which an MSYS2 install can lack: the outputs are
# compared by the helper every test uses, which falls back to cksum.
. "$(cd "$(dirname "$0")" && pwd)/../lib/same_bytes.sh"
same_output() {
    same_bytes "$1" "$2"
}

show_diff() {
    if command -v diff >/dev/null 2>&1; then
        echo "stdout differs (--- -O2 / +++ -O0):"
        diff -u "$1" "$2" | sed '1,2d' | head -n 30
    else
        echo "stdout differs; -O2, first 15 lines:"; head -n 15 "$1"
        echo "-O0, first 15 lines:"; head -n 15 "$2"
    fi
}

# `opt_diff_one.sh --self-check <dir>`: proves same_output tells two outputs
# apart AND matches two equal ones. Checking only the first passes when the
# tool is missing, since a command that cannot run reads as "different".
if [ "$1" = "--self-check" ]; then
    printf 'a\n' > "$2/self.a"
    printf 'b\n' > "$2/self.b"
    printf 'a\n' > "$2/self.c"
    same_output "$2/self.a" "$2/self.b" && exit 1
    same_output "$2/self.a" "$2/self.c" || exit 1
    exit 0
fi

f="$1"
tmpdir="$2"
root="$3"

# The limits run_ae_test.sh puts on the same programs, by the same means
# (on Windows a job object, never a signal: tests/lib/sweep_timeout.sh).
. "$root/tests/lib/sweep_timeout.sh"
sweep_timeout_bound TO "$root" "${AE_TEST_TIMEOUT:-120}"
sweep_timeout_bound BTO "$root" "${AE_TEST_BUILD_TIMEOUT:-600}"

. "$root/tests/scripts/sweep_name.sh"
name=$(echo "$f" | sed "$SWEEP_NAME_SED")
dir=$(dirname "$f")
base=$(basename "$f")
res="$tmpdir/res"
work="$tmpdir/work/$name"
mkdir -p "$work/O2" "$work/O0" "$work/run"

# build <level> <flags>: the binary lands in $work/<level>/test_<name>.
build() {
    out="$work/$1/test_$name"
    if [ -d "$dir/lib" ]; then
        cmd="cd $dir && $root/build/ae build $base $2 -o $out"
    else
        cmd="$root/build/ae build $f $2 -o $out"
    fi
    $BTO sh -c "$cmd" >"$work/$1.build" 2>&1
    brc=$?
    if [ $brc -ne 0 ]; then
        what="build failed"
        [ $brc -eq 124 ] && what="build timed out"
        { echo "$what at $1 (exit $brc):"; tail -n 15 "$work/$1.build"; } > "$res/$name.why"
        echo "  [FAIL] $name ($what at $1)"
        touch "$res/FAIL_$name"
        rm -rf "$work"
        exit 0
    fi
}

# run <level>: moves that level's binary to the shared path and runs it.
run() {
    ext=""
    [ -f "$work/$1/test_$name.exe" ] && ext=".exe"
    # Two binaries that never ran would agree on exit 127 and no output.
    if [ ! -f "$work/$1/test_$name$ext" ]; then
        echo "the build at $1 succeeded but left no binary" > "$res/$name.why"
        echo "  [FAIL] $name (no binary at $1)"
        touch "$res/FAIL_$name"
        rm -rf "$work"
        exit 0
    fi
    mv "$work/$1/test_$name$ext" "$work/run/test_$name$ext"
    $TO "$work/run/test_$name$ext" >"$work/$1.out" 2>"$work/$1.err"
    echo $? > "$work/$1.rc"
    rm -f "$work/run/test_$name$ext"
}

build O2 ""
build O0 "--quick"
run O2
run O0

rc2=$(cat "$work/O2.rc")
rc0=$(cat "$work/O0.rc")

reason=$(awk -v want="$f" '
    /^[[:space:]]*#/ { next }
    NF == 0          { next }
    $1 == want       { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }
' "$root/tests/differential/opt_diff_carveouts.txt" 2>/dev/null)

if [ "$rc2" != "$rc0" ]; then
    # stdout as well as stderr: a test's own check (`println("FAIL ...")`
    # then `exit(1)`) says what failed on stdout, and stderr alone left the
    # receive_arm_heap_locals failure on main with no reason at all.
    { echo "exit code differs: -O2 exited $rc2, -O0 exited $rc0"
      echo "(-O0 stdout, last 10 lines)"; tail -n 10 "$work/O0.out"
      echo "(-O0 stderr, last 10 lines)"; tail -n 10 "$work/O0.err"
      echo "(-O2 stdout, last 10 lines)"; tail -n 10 "$work/O2.out"
      echo "(-O2 stderr, last 10 lines)"; tail -n 10 "$work/O2.err"; } > "$res/$name.why"
    echo "  [DIFF] $name (exit code: -O2 $rc2, -O0 $rc0)"
    touch "$res/DIFF_$name"
elif [ -n "$reason" ]; then
    echo "$reason" > "$res/$name.why"
    echo "  [CARVED] $name"
    touch "$res/CARVED_$name"
elif ! same_output "$work/O2.out" "$work/O0.out"; then
    show_diff "$work/O2.out" "$work/O0.out" > "$res/$name.why"
    echo "  [DIFF] $name (stdout)"
    touch "$res/DIFF_$name"
else
    echo "  [SAME] $name"
    touch "$res/SAME_$name"
fi

rm -rf "$work"
