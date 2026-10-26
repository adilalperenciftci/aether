#!/bin/sh
# Regression (#3150): a `try` where a value goes is one error that names
# the statement form, and nothing after it is misread.
#
# `r = try { work() } catch e { ... }` was reported as "'try' is a reserved
# keyword and cannot be used as an identifier"; the recovery then took only
# `try {` as the rest of the line, so the try block's own `}` closed the
# function and its `catch` was read at top level: six errors. Now it is one
# E0100, "`try` is a statement and gives no value", at the `try`, with the
# statement form in the help line, and the whole try statement, its catch
# included, is stepped over. A value position of any kind behaves alike
# (here a `return` too), and a `try` statement written as one compiles.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ] && [ ! -x "$AETHERC.exe" ]; then
    echo "  [SKIP] try_statement_value: aetherc not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0

# refuse NAME WHERE: $TMP/NAME.ae is refused with one error, the try one, at
# WHERE (line:column), with the statement form as its help.
refuse() {
    name="$1"; where="$2"
    out="$("$AETHERC" --check "$TMP/$name.ae" 2>&1)"
    errors=$(printf '%s\n' "$out" | grep -c '^error')
    first=$(printf '%s\n' "$out" | grep -m1 '^error')
    at=$(printf '%s\n' "$out" | grep -m1 -- '-->' | sed 's/.*\.ae://')
    if [ "$first" != 'error[E0100]: `try` is a statement and gives no value' ]; then
        echo "  [FAIL] $name: expected the try-statement error, got: $first"
        fail=1
    elif [ "$errors" -ne 1 ] || [ "$at" != "$where" ]; then
        echo "  [FAIL] $name: $errors error(s), the first at $at (expected 1, at $where)"
        printf '%s\n' "$out" | sed 's/^/        /' | head -20
        fail=1
    elif ! printf '%s\n' "$out" | grep -q 'help: bind the value inside it: `try { r = work() } catch e { ... }`'; then
        echo "  [FAIL] $name: no help line with the statement form"
        fail=1
    else
        echo "  [PASS] $name"
    fi
}

cat > "$TMP/assign.ae" <<'AEOF'
work() -> int {
    return 42
}

main() {
    r = try {
        work()
    } catch e {
        println("caught ${e}")
    }
    println("after")
}

later(x: int) -> int {
    return x
}
AEOF
refuse assign 6:9

cat > "$TMP/returned.ae" <<'AEOF'
work() -> int {
    return 42
}

value() -> int {
    return try { work() } catch e { 0 }
}

main() {
    println(value())
}
AEOF
refuse returned 6:12

cat > "$TMP/statement.ae" <<'AEOF'
work() -> int {
    return 42
}

main() {
    r = 0
    try {
        r = work()
    } catch e {
        println("caught ${e}")
    }
    println(r)
}
AEOF
if "$AETHERC" --check "$TMP/statement.ae" >/dev/null 2>&1; then
    echo "  [PASS] a try statement compiles"
else
    echo "  [FAIL] a try statement no longer compiles"
    fail=1
fi

exit $fail
