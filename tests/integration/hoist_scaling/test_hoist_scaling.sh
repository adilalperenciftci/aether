#!/bin/sh
# Regression (#3083): hoisting answers each name from one walk of its body,
# at any number of names.
#
# The checker and codegen walked the function body once per name bound in
# its branches (the joins, the written type, the first binding, whether a
# name is read), and the unused-variable pass compared every reference with
# every local: a function with 3000 such names took 2.6 s to compile. Each
# question now reads what one walk of the body gathered. A function could
# also hoist at most 64 names out of its branches: the 65th, bound in an arm
# and read after it, was "Undefined variable".
#
# This is the functional half: a generated main large enough that every
# indexed path is taken, checking the answers. The timing half is the table
# in #3083; a wall-clock assertion would be a flake on a loaded runner.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] hoist_scaling: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
N=300

awk -v n="$N" 'BEGIN {
    print "import std.string"
    print ""
    print "main() {"
    print "    c = 1"
    print "    long total = 0"
    for (i = 0; i < n; i++) {
        # One arm binds it, a read after the if hoists it (past 64 names).
        printf "    if c > 0 {\n        a%d = %d\n    }\n", i, i
        # Both arms bind it: an int beside a long joins to a long.
        printf "    if c > %d {\n        b%d = 4000000000\n    } else {\n        b%d = %d\n    }\n", i + 5, i, i, i
        # `null` beside a string joins to a string.
        printf "    if c > 0 {\n        s%d = \"s\"\n    } else {\n        s%d = null\n    }\n", i, i
        # A binding that writes its type is the type.
        printf "    if c > 0 {\n        uint64 w%d = 7\n    } else {\n        w%d = 1\n    }\n", i, i
        printf "    c = c + 1\n"
        printf "    total = total + a%d + b%d + string.length(s%d) + w%d\n", i, i, i, i
    }
    print "    unused_one = 5"
    print "    println(\"total=${total} c=${c}\")"
    print "}"
}' > "$tmp/big.ae"

OUT="$(AETHER_HOME="$ROOT" "$AE" run "$tmp/big.ae" 2>&1)"
RC=$?
if [ $RC -ne 0 ]; then
    echo "  [FAIL] hoist_scaling: the $N-name program did not compile/run"
    echo "$OUT" | grep -E "error|rror:" | head -6
    exit 1
fi

# c is i + 1 at the i-th round, so `c > i + 5` never holds and b_i = i (its
# other arm only makes it a long). total = sum(a_i) + sum(b_i) + n * len("s")
# + n * 7 = n(n-1) + 8n.
want_total=$((N * (N - 1) + 8 * N))
want_c=$((N + 1))
fail=0
if ! echo "$OUT" | grep -Fxq "total=$want_total c=$want_c"; then
    echo "  [FAIL] hoist_scaling: expected total=$want_total c=$want_c"
    echo "$OUT" | tail -4
    fail=1
fi
warned="$(echo "$OUT" | grep -c "unused variable")"
if [ "$warned" -ne 1 ] || ! echo "$OUT" | grep -q "unused variable 'unused_one'"; then
    echo "  [FAIL] hoist_scaling: expected one unused-variable warning, for unused_one ($warned)"
    echo "$OUT" | grep "unused variable" | head -4
    fail=1
fi
[ "$fail" -eq 0 ] || exit 1
echo "  [PASS] hoist_scaling: $N names hoisted out of branches, joined and read through the indexes"
