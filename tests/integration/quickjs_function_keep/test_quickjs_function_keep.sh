#!/bin/sh
# contrib.quickjs's `function` takes a typed callback, `fn(@keep ptr, int, int)
# -> int`, not a bare `@keep fn`. A bare `fn` borrows every parameter it is
# handed, so a host function that kept the runtime pointer it is called with
# (a registry, the widget callbacks a page API registers) was refused (E0902)
# and sae declared its own `extern qjs_function` with the type to get past it.
#
# Accepted: a named function and closures (typed or taking the modes from the
# type) that keep `q`, and the callback running for real. Refused: a closure
# that declares `q` borrowed and keeps it, and a bare `fn` value handed on.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
NAME=quickjs_function_keep

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }
[ -f "$ROOT/contrib/quickjs/amalgamation/quickjs-amalgam.c" ] ||
    sh "$ROOT/scripts/fetch-quickjs-amalgamation.sh" >/dev/null 2>&1 ||
    { echo "  [SKIP] $NAME: the QuickJS amalgamation could not be fetched"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

cat > "$TMP/ok.ae" <<'AE'
import contrib.quickjs
import std.list

var registry: ptr = null

hold(q: @keep ptr, this_h: int, args: int) -> int {
    list.add(registry, q)
    return quickjs.new_int(q, list.size(registry))
}

main() {
    registry = list.new()
    q = quickjs.runtime(0, 0)
    f1 = quickjs.function(q, "named", 0, hold)
    f2 = quickjs.function(q, "typed", 0, |q: @keep ptr, this_h: int, args: int| {
        list.add(registry, q)
        return quickjs.new_int(q, list.size(registry))
    })
    f3 = quickjs.function(q, "inferred", 0, |q, this_h, args| {
        list.add(registry, q)
        return quickjs.new_int(q, list.size(registry))
    })
    quickjs.set_global(q, "named", f1)
    quickjs.set_global(q, "typed", f2)
    quickjs.set_global(q, "inferred", f3)
    quickjs.release(q, f1)
    quickjs.release(q, f2)
    quickjs.release(q, f3)
    n, err = quickjs.eval(q, "named() * 100 + typed() * 10 + inferred()", "ok.js")
    if err != "" { println("ERR: ${err}") } else { println("kept=${quickjs.to_int(q, n)} size=${list.size(registry)}") }
    quickjs.release(q, n)
    quickjs.dispose(q)
}
AE
if ! out=$(cd "$TMP" && "$AE" build ok.ae -o ok 2>&1); then
    echo "  [FAIL] $NAME: a callback that keeps q was refused:"
    echo "$out" | sed 's/^/        /'
    fails=$((fails + 1))
else
    got=$("$TMP/ok" 2>&1)
    [ "$got" = "kept=123 size=3" ] || { echo "  [FAIL] $NAME: ran wrong: '$got'"; fails=$((fails + 1)); }
fi

# refused <name> <text>: <name>.ae is refused with E0902 naming <text>.
refused() {
    out=$(cd "$TMP" && "$AE" check "$1.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $1: accepted"; fails=$((fails + 1)); return
    fi
    case "$out" in
        *"error[E0902]"*"$2"*) ;;
        *) echo "  [FAIL] $1: not E0902 \"$2\":"; echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

cat > "$TMP/borrowed_q.ae" <<'AE'
import contrib.quickjs
import std.list
var registry: ptr = null
main() {
    registry = list.new()
    q = quickjs.runtime(0, 0)
    h = quickjs.function(q, "hold", 0, |q: ptr, this_h: int, args: int| {
        list.add(registry, q)
        return 0
    })
    quickjs.release(q, h)
}
AE
refused borrowed_q "'q' is a borrowed \`ptr\` parameter"

cat > "$TMP/bare_fn.ae" <<'AE'
import contrib.quickjs
install(q: ptr, f: fn) {
    h = quickjs.function(q, "x", 0, f)
    quickjs.release(q, h)
}
main() { }
AE
refused bare_fn "'f' is a borrowed \`fn\` parameter"

[ "$fails" -eq 0 ] || exit 1
echo "  [PASS] $NAME: quickjs.function takes fn(@keep ptr, int, int) -> int"
exit 0
