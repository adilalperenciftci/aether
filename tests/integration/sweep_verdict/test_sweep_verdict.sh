#!/bin/sh
# The end of `make test-ae` (#3111): tests/scripts/sweep_unreported.sh names
# every listed test that left no marker, and tests/scripts/sweep_verdict.sh
# passes only a tally with no failure in which every listed test reported.
#
# A local sweep on a machine that stopped starting processes ran 29 of its
# shell tests, its xargs returned 0, and nothing compared what reported with
# what was listed; an earlier one stopped before its tally and make still
# exited 0. Each verdict below has to come out as it says, and a test run by
# the sweep's own runner has to be found under the name it reports by.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
UNREPORTED="$ROOT/tests/scripts/sweep_unreported.sh"
VERDICT="$ROOT/tests/scripts/sweep_verdict.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "  [FAIL] sweep_verdict: $1"; exit 1; }

# --- sweep_unreported.sh on a sweep that lost two of five tests ---
# Paths relative to a root of their own, as the sweep lists them.
mkdir -p "$TMP/tree/tests/integration/dir_unit" "$TMP/tree/tests/integration/one" \
         "$TMP/tree/sweep"
: > "$TMP/tree/tests/integration/dir_unit/test_a.sh"
: > "$TMP/tree/tests/integration/dir_unit/test_b.sh"
: > "$TMP/tree/tests/integration/dir_unit/helper.sh"
: > "$TMP/tree/tests/integration/one/test_one.sh"
printf '%s\n' tests/regression/test_x.ae std/fs/test_fs.ae > "$TMP/tree/sweep/units_ae.txt"
printf '%s\n' tests/integration/one/test_one.sh tests/integration/dir_unit \
    > "$TMP/tree/sweep/units_sh.txt"
: > "$TMP/tree/sweep/PASS_regression_test_x"
: > "$TMP/tree/sweep/SKIP_integration_one_test_one"
: > "$TMP/tree/sweep/FAIL_integration_dir_unit_test_a"
listed=$(cd "$TMP/tree" && sh "$UNREPORTED" sweep "$TMP/unreported.txt") \
    || fail "sweep_unreported.sh exited $?"
[ "$listed" = 5 ] || fail "5 tests were listed (two .ae, a script, a directory of two), it counted '$listed'"
want="$(printf '%s\n' integration_dir_unit_test_b std_fs_test_fs)"
[ "$(cat "$TMP/unreported.txt")" = "$want" ] \
    || fail "the two tests with no marker are integration_dir_unit_test_b and std_fs_test_fs, it named: $(tr '\n' ' ' < "$TMP/unreported.txt")"

# --- the sweep's own runner reports under the name sweep_unreported.sh uses ---
mkdir -p "$TMP/unit" "$TMP/run"
printf 'echo "  [PASS] fine"\n' > "$TMP/unit/test_fine.sh"
printf '%s\n' "$TMP/unit" > "$TMP/run/units_sh.txt"
sh "$ROOT/tests/scripts/run_ae_sh_dir.sh" "$TMP/unit" "$TMP/run" "$ROOT" > "$TMP/runner.log" 2>&1
listed=$(sh "$UNREPORTED" "$TMP/run" "$TMP/run_unreported.txt") || fail "sweep_unreported.sh exited $? on the runner's markers"
if [ "$listed" != 1 ] || [ -s "$TMP/run_unreported.txt" ]; then
    fail "a test the runner reported reads as never reported (listed '$listed', unreported: $(cat "$TMP/run_unreported.txt"); runner: $(cat "$TMP/runner.log"))"
fi

# --- sweep_verdict.sh ---
v="$TMP/test-ae.verdict"
expect() { # expect <status> <label> <verdict line or -> [<grep pattern>]
    if [ "$3" = - ]; then rm -f "$v"; else printf '%s\n' "$3" > "$v"; fi
    out=$(sh "$VERDICT" "$v" "$TMP/unreported.txt" 2>&1)
    rc=$?
    [ "$rc" = "$1" ] || fail "$2: exit $rc, expected $1 ($out)"
    if [ -n "${4:-}" ]; then
        printf '%s\n' "$out" | grep -q -- "$4" || fail "$2: no '$4' in: $out"
    fi
}
expect 0 "a complete pass" "5 0 0 5 5"
expect 0 "skips count as reported" "3 0 2 5 5"
expect 1 "no tally" - "without its tally"
expect 1 "a failure" "4 1 0 5 5" "not a pass"
expect 1 "tests that never reported" "3 0 0 3 5" "3 of the 5"
expect 1 "and their names" "3 0 0 3 5" "std_fs_test_fs"
expect 1 "a tally without the listed count" "5 0 0 5" "unreadable"
expect 1 "an empty field" "5 0 0 5 " "unreadable"
expect 1 "a field too many" "5 0 0 5 5 1" "unreadable"
expect 1 "a total that does not add up" "5 0 0 4 4" "not a pass"
expect 1 "nothing ran" "0 0 0 0 0" "not a pass"

echo "  [PASS] sweep_verdict: unreported tests are named, and only a complete tally with no failure passes"
