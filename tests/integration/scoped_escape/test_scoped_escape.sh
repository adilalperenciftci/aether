#!/bin/sh
# Issue #521: a `@scoped` binding must not outlive its block. Each reject_*.ae
# below escapes a @scoped value a different way and MUST fail to build with the
# "@scoped ... escapes its block" diagnostic. (The allowed shapes — a derived
# scalar escaping, local-only use — are covered by the regression test
# test_issue521_scoped.ae.) The directory is pruned from the generic .ae
# runner so this driver owns the negative cells.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ]; then
    echo "  [SKIP] scoped_escape: $AE not built"
    exit 0
fi

TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT

check_rejected() {
    name="$1"
    if "$AE" build "$SCRIPT_DIR/$name.ae" -o "$TMPDIR/out" >"$TMPDIR/$name.log" 2>&1; then
        echo "  [FAIL] scoped_escape: $name.ae compiled (should be rejected)"
        exit 1
    fi
    if ! grep -q "escapes its block" "$TMPDIR/$name.log"; then
        echo "  [FAIL] scoped_escape: $name.ae failed without the @scoped diagnostic"
        sed 's/^/    /' "$TMPDIR/$name.log" | head -10
        exit 1
    fi
}

# #3001: the help names a value derived from the binding in Aether for its
# type. It suggested `s.len()`, which Aether does not have.
check_help() {
    name="$1"; want="$2"
    if ! grep -qF "$want" "$TMPDIR/$name.log"; then
        echo "  [FAIL] scoped_escape: $name.ae help does not suggest $want:"
        grep -F "help:" "$TMPDIR/$name.log" | sed 's/^/    /' | head -3
        exit 1
    fi
    if grep -qF ".len()" "$TMPDIR/$name.log"; then
        echo "  [FAIL] scoped_escape: $name.ae help suggests .len(), which is not Aether"
        exit 1
    fi
}

check_rejected reject_return
check_help reject_return '`string.length(s)`'
check_rejected reject_alias
check_rejected reject_closure
check_rejected reject_container
# #3001: the sequence cons is a container insert too; the list named
# `seq.cons`, which std does not have.
check_rejected reject_seq_cons
check_rejected reject_list_return
check_help reject_list_return '`list.size(l)`'
check_rejected reject_slice_return
check_help reject_slice_return '`v.len`'

echo "  [PASS] scoped_escape: return / alias / closure-capture / container-insert / seq-cons all rejected, with Aether in the help"
exit 0
