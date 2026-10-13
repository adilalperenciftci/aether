#!/bin/sh
# #2813: what calling a function can change (order_fn_effects, the
# evaluation-order rule of #2478) is solved over the call graph in time
# linear in its size.
#
# A chain of 8000 functions, each calling the next and only the last
# writing through its pointer parameter, asked about once
# (`show(q.n, f0(p, 3))`): one fixed point over every reached function took
# a pass per level, 90 s for this chain, and the recursive solve before it
# ran out of stack. Solved by strongly connected component it takes well
# under a second; the bound here is generous for slow runners.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
[ -x "$AETHERC" ] || [ ! -x "$AETHERC.exe" ] || AETHERC="$AETHERC.exe"

if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] order_effects_scaling: aetherc not built"
    exit 0
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

N=8000
LIMIT=20

awk -v n="$N" 'BEGIN {
    print "extern malloc(size: int) -> ptr"
    print ""
    print "struct Box {"
    print "    n: int"
    print "}"
    print ""
    print "show(a: int, b: int) -> int {"
    print "    return a * 1000 + b"
    print "}"
    for (i = 0; i < n; i++) {
        print ""
        print "f" i "(b: *Box, d: int) -> int {"
        if (i + 1 < n) {
            print "    return f" (i + 1) "(b, d + 1)"
        } else {
            print "    b.n = 5"
            print "    return 2"
        }
        print "}"
    }
    print ""
    print "main() {"
    print "    p = malloc(sizeof(Box)) as *Box"
    print "    q = p"
    print "    p.n = 1"
    print "    r = show(q.n, f0(p, 3))"
    print "    println(\"${r}\")"
    print "}"
}' > "$TMPDIR/chain.ae"

start=$(date +%s)
"$AETHERC" "$TMPDIR/chain.ae" "$TMPDIR/chain.c" > "$TMPDIR/aetherc.log" 2>&1
rc=$?
elapsed=$(( $(date +%s) - start ))

if [ "$rc" -ne 0 ]; then
    echo "  [FAIL] order_effects_scaling: aetherc failed (exit $rc) on a chain of $N calls"
    tail -5 "$TMPDIR/aetherc.log" | sed 's/^/    /'
    exit 1
fi
if [ "$elapsed" -gt "$LIMIT" ]; then
    echo "  [FAIL] order_effects_scaling: a chain of $N calls took ${elapsed}s to compile (limit ${LIMIT}s)"
    exit 1
fi
# The read of q.n comes first, ahead of the call that writes it.
if ! grep -q "_eo[0-9]* = \|_AE_SEQ_LET" "$TMPDIR/chain.c"; then
    echo "  [FAIL] order_effects_scaling: q.n is not evaluated ahead of f0(p, 3)"
    exit 1
fi
echo "  [PASS] order_effects_scaling: a chain of $N calls solved in ${elapsed}s"
exit 0
