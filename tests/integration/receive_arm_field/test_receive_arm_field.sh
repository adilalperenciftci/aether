#!/bin/sh
# Regression (#3164): a receive arm that names a field its message does not
# have is one error at the arm, not a C error.
#
# An arm binds a message's fields by name: `Connect(next)`, or
# `Connect(next: n)` to bind the field `next` as `n`. `Connect(n)`, a
# positional reading, went on with `n` untyped and codegen's `_pattern->n`
# failed in C: "'Connect' has no member named 'n'". It is now one E0200 at
# the `n`, naming the fields the message has, with the rename form as its
# help; a message with no fields says so. The two right forms compile.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ] && [ ! -x "$AETHERC.exe" ]; then
    echo "  [SKIP] receive_arm_field: aetherc not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# program NAME ARM: an actor whose arm is ARM (on line 12), over
# `message Connect { next: actor_ref, tries: int }` and `message Ping {}`.
# A `_` arm takes the Connect main sends whatever ARM is (#385 refuses a
# send no arm takes).
program() {
    printf 'message Connect {\n    next: actor_ref\n    tries: int\n}\n\nmessage Ping {}\n\nactor A {\n    state seen = 0\n\n    receive {\n        %s -> {\n            seen = seen + 1\n        }\n        _ -> {}\n    }\n}\n\nmain() {\n    a = spawn(A())\n    a ! Connect { next: a, tries: 1 }\n    wait_for_idle()\n}\n' "$2" > "$TMP/$1.ae"
}

# refuse NAME ARM WHERE MESSAGE HELP
refuse() {
    program "$1" "$2"
    out="$("$AETHERC" --check "$TMP/$1.ae" 2>&1)"
    errors=$(printf '%s\n' "$out" | grep -c '^error')
    first=$(printf '%s\n' "$out" | grep -m1 '^error')
    at=$(printf '%s\n' "$out" | grep -m1 -- '-->' | sed 's/.*\.ae://')
    if [ "$first" != "error[E0200]: $4" ]; then
        echo "  [FAIL] $1: expected \"error[E0200]: $4\", got: $first"
        fail=1
    elif [ "$errors" -ne 1 ] || [ "$at" != "$3" ]; then
        echo "  [FAIL] $1: $errors error(s), the first at $at (expected 1, at $3)"
        printf '%s\n' "$out" | sed 's/^/        /' | head -12
        fail=1
    elif ! printf '%s\n' "$out" | grep -q -F "help: $5"; then
        echo "  [FAIL] $1: no help line \"$5\""
        printf '%s\n' "$out" | sed 's/^/        /' | head -12
        fail=1
    else
        echo "  [PASS] $1"
    fi
}

refuse positional 'Connect(n)' 12:17 \
    "message 'Connect' has no field 'n'; its fields are next, tries" \
    'an arm binds a field by its name: `Connect(next)`, or `Connect(next: n)` to bind it as `n`'
refuse second 'Connect(next, count)' 12:23 \
    "message 'Connect' has no field 'count'; its fields are next, tries" \
    'an arm binds a field by its name: `Connect(next)`, or `Connect(next: count)` to bind it as `count`'
refuse no_fields 'Ping(x)' 12:14 \
    "message 'Ping' has no field 'x'; it has no fields" \
    'match it with no bindings: `Ping -> { ... }`'

for arm in 'Connect(next)' 'Connect(next: n, tries)' 'Ping'; do
    program ok "$arm"
    if "$AETHERC" --check "$TMP/ok.ae" >/dev/null 2>&1; then
        echo "  [PASS] $arm compiles"
    else
        echo "  [FAIL] $arm no longer compiles"
        "$AETHERC" --check "$TMP/ok.ae" 2>&1 | sed 's/^/        /' | head -8
        fail=1
    fi
done

exit $fail
