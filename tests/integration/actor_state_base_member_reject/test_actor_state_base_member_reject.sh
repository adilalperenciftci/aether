#!/bin/sh
# #3094: a generated actor keeps the runtime's actor fields in a member
# named `_aether_base`, so every other name is a normal state, the base's
# field names (`id`, `active`, `mailbox`...) included. A state named
# `_aether_base` itself is refused by the checker with a message naming
# it, rather than failing in the C compiler as a duplicate member.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

SRC="$SCRIPT_DIR/base_member.ae"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if "$AETHERC" "$SRC" "$TMPDIR/out.c" >"$TMPDIR/err.log" 2>&1; then
    echo "  [FAIL] aetherc accepted a state named _aether_base"
    exit 1
fi

if ! grep -q "a state cannot be named '_aether_base'" "$TMPDIR/err.log"; then
    echo "  [FAIL] the error does not name the state"
    cat "$TMPDIR/err.log"
    exit 1
fi

# The checker's error, not a C compiler's: no C was written.
if grep -q "duplicate member" "$TMPDIR/err.log"; then
    echo "  [FAIL] the state reached the C compiler"
    cat "$TMPDIR/err.log"
    exit 1
fi

echo "  [PASS] actor_state_base_member_reject: a state named _aether_base is refused"
