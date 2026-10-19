#!/bin/sh
# A named argument goes to the parameter it names (#2850). Before, names
# were not looked at: `sub(a: 1, c: 2)`, `sub(a: 1, a: 2)` and
# `sub(1, a: 2)` compiled, each argument passed in the place it was
# written. Now a name no parameter has, a parameter given twice, a
# positional argument after a named one, a parameter with no default left
# out, and a named argument to a callee whose parameters have no names (a
# closure, through its name or call()) are errors, each at the argument.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AETHERC="$AETHERC$EXE_EXT"
if [ ! -x "$AETHERC" ]; then
    echo "  [SKIP] named_args_reject: aetherc not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0

cat > "$tmp/bad.ae" <<'AE'
sub(a: int, b: int) -> int {
    return a - b
}

main() {
    x = sub(a: 1, c: 2)
    y = sub(a: 1, a: 2)
    z = sub(1, a: 2)
    q = sub(b: 1)
    r = sub(a: 1, 2)
    f = |p: int| { return p }
    s = f(p: 1)
    t = call(f, p: 1)
    println("${x} ${y} ${z} ${q} ${r} ${s} ${t}")
}
AE
out="$(AETHER_HOME="$ROOT" "$AETHERC" --check "$tmp/bad.ae" 2>&1)"
for want in \
    "bad.ae:6:19 .*'sub' has no parameter named 'c'" \
    "bad.ae:7:19 .*parameter 'a' of 'sub' is given twice" \
    "bad.ae:8:16 .*parameter 'a' of 'sub' is given twice" \
    "bad.ae:9:9 .*the call of 'sub' gives no argument for parameter 1 'a'" \
    "bad.ae:10:19 .*a positional argument after a named one" \
    "bad.ae:12:11 .*named argument 'p' in a call of a closure, whose parameters have no names" \
    "bad.ae:13:17 .*named argument 'p' in a call of a closure, whose parameters have no names"; do
    if ! printf '%s\n' "$out" | awk '/^error/ { m = $0; next } /-->/ && m != "" { print $2 " " m; m = "" }' | grep -q "$want"; then
        echo "  [FAIL] named_args_reject: no diagnostic matching: $want"
        fail=1
    fi
done
if ! printf '%s' "$out" | grep -q 'its parameters are a, b'; then
    echo "  [FAIL] named_args_reject: the help does not list the parameters"
    fail=1
fi
[ $fail -ne 0 ] && printf '%s\n' "$out" | grep -E "^error|-->|help" | head -20 | sed 's/^/        |/'

if [ $fail -eq 0 ]; then
    echo "  [PASS] named_args_reject: unknown, repeated, misplaced and missing named arguments are refused"
fi
exit $fail
