#!/bin/sh
# #2752: `ae test a.ae b.ae` ran a.ae, dropped b.ae without a word and
# reported "1 passed, 0 failed, 1 total", so a failing test in the second file
# passed. Every non-flag argument was assigned to one `target`, and only the
# last one assigned was collected. Now every file and directory named runs,
# the run fails if any test in any of them does, and a target that does not
# exist is an error instead of a quiet fallback to ./tests.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] ae_test_many_targets: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "  [FAIL] $1"; exit 1; }

cd "$TMP" || fail "cannot enter $TMP"
printf 'main() {\n    println("first file ran")\n}\n' > one_test.ae
printf 'main() {\n    println("second file ran")\n    exit(1)\n}\n' > two_test.ae
mkdir -p suite/tests
printf 'main() {\n    println("dir test ran")\n}\n' > suite/tests/test_in_dir.ae

# The issue's own repro: the failing file second, then first.
out=$("$AE" test one_test.ae two_test.ae 2>&1)
rc=$?
[ "$rc" -ne 0 ] || fail "a failing test in the second file passed the run: $out"
printf '%s\n' "$out" | grep -q "two_test.ae" || fail "two_test.ae never ran: $out"
printf '%s\n' "$out" | grep -q "1 passed, 1 failed, 2 total" \
    || fail "expected '1 passed, 1 failed, 2 total', got: $(printf '%s\n' "$out" | tail -1)"

out=$("$AE" test two_test.ae one_test.ae 2>&1)
[ $? -ne 0 ] || fail "a failing test in the first file passed the run: $out"
printf '%s\n' "$out" | grep -q "1 passed, 1 failed, 2 total" \
    || fail "with the order swapped, got: $(printf '%s\n' "$out" | tail -1)"

# Files and directories mix, in the order given; --list shows exactly that.
listed=$("$AE" test --list one_test.ae suite two_test.ae 2>&1 | tr -d '\r')
n=$(printf '%s\n' "$listed" | grep -c .)
[ "$n" = 3 ] || fail "--list over two files and a directory listed $n entries: $listed"
first=$(printf '%s\n' "$listed" | head -1)
last=$(printf '%s\n' "$listed" | tail -1)
[ "$first" = "one_test.ae" ] && [ "$last" = "two_test.ae" ] \
    || fail "--list did not keep the order given: $listed"
printf '%s\n' "$listed" | grep -q "test_in_dir.ae" \
    || fail "the directory's test was not collected: $listed"

out=$("$AE" test one_test.ae suite 2>&1) \
    || fail "two passing targets failed the run: $out"
printf '%s\n' "$out" | grep -q "2 passed, 0 failed, 2 total" \
    || fail "a file plus a directory, got: $(printf '%s\n' "$out" | tail -1)"

# A target that does not exist is named, never replaced by ./tests.
mkdir -p tests
printf 'main() {\n    println("unrelated")\n}\n' > tests/test_unrelated.ae
out=$("$AE" test one_test.ae missing_test.ae 2>&1)
[ $? -ne 0 ] || fail "a missing target passed the run: $out"
printf '%s\n' "$out" | grep -q "missing_test.ae" \
    || fail "the error does not name the missing target: $out"
printf '%s\n' "$out" | grep -q "test_unrelated" \
    && fail "a missing target fell back to running ./tests: $out"

# One target, and none, behave as before.
out=$("$AE" test one_test.ae 2>&1) || fail "a single passing file failed: $out"
printf '%s\n' "$out" | grep -q "1 passed, 0 failed, 1 total" \
    || fail "a single file, got: $(printf '%s\n' "$out" | tail -1)"
out=$("$AE" test 2>&1) || fail "the default tests/ run failed: $out"
printf '%s\n' "$out" | grep -q "1 passed, 0 failed, 1 total" \
    || fail "no target (./tests), got: $(printf '%s\n' "$out" | tail -1)"

echo "  [PASS] ae_test_many_targets: every file and directory named runs, and any failure fails the run"
