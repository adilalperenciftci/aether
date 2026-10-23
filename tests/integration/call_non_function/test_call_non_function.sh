#!/bin/sh
# #3099: a call through an expression whose value is not a function is
# refused in the words of what was written, before C. Calls through such a
# callee are lowered to the builtin `call(f, ...)`, whose own message named
# a builtin the program never wrote ("call() needs a closure, but the first
# argument has type int").
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
if [ ! -x "$AETHERC" ] && [ ! -x "$AETHERC.exe" ]; then echo "  [SKIP] call_non_function: $AETHERC not built"; exit 0; fi
export AETHER_HOME="$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
fail=0

# <name> <pattern the diagnostic must match>; the program is on stdin.
refused() {
    name="$1"; want="$2"
    cat > "$tmp/$name.ae"
    if "$AETHERC" "$tmp/$name.ae" "$tmp/$name.c" >"$tmp/$name.log" 2>&1; then
        echo "  [FAIL] call_non_function: $name compiled (it must be refused before C)"
        fail=1; return
    fi
    if ! grep -qF "$want" "$tmp/$name.log" || grep -qF "call()" "$tmp/$name.log"; then
        echo "  [FAIL] call_non_function: $name refused, but not with: $want"
        sed 's/^/        /' "$tmp/$name.log" | head -6
        fail=1
    fi
}

refused element "the value called here is not a function: it has type int" <<'AE'
main() {
    xs = [1, 2]
    xs[0]()
}
AE
refused result "the value called here is not a function: it has type string" <<'AE'
name() -> string {
    return "a"
}
main() {
    name()()
}
AE

[ "$fail" = 0 ] && echo "  [PASS] call_non_function: a call through a value that is not a function is refused as such"
exit "$fail"
