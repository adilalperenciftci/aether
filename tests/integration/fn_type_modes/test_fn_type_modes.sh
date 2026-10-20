#!/bin/sh
# `@keep` and `@into` are part of a function type (#2980): `fn(@keep ptr,
# float)` is a closure type whose first parameter keeps what it is given.
#
# A call through a value of the type is checked as a direct call is (a
# borrowed `ptr` given to a `@keep` parameter, a string without
# `string.keep`, an `@into` result that escapes: E0902). A closure literal
# may declare the modes, or take them with the types for the parameters it
# leaves untyped; a function with such a parameter is a value of its type.
# A function may stand where its modes, or stronger ones, are expected
# (borrowed, then `@into`, then `@keep`), never the reverse: not in a bare
# `fn`, in a weaker closure type, in a `ptr` (the box opens to a `fn`), or as
# a typed C function pointer, whose parameters borrow.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] fn_type_modes: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# refused <name> <line:col> <code> <text>: `ae check` refuses <name>.ae with
# <code> at that position, its message containing <text>.
refused() {
    name="$1"; at="$2"; code="$3"; text="$4"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $name: accepted"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    case "$out" in
        *"error[$code]"*"$text"*"$name.ae:$at"*) ;;
        *) echo "  [FAIL] $name: not $code \"$text\" at $at:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

accepted() {
    name="$1"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -ne 0 ]; then
        echo "  [FAIL] $name: refused"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
}

# The common head: a keeping setter (vg's element_set_fill) and a builder.
head_ae() {
    cat <<'AE'
import std.list
import std.string

var registry: ptr = null
var kept: ptr = null

set_fill(el: @keep ptr, t: float) { list.add(registry, el) }
view(p: @into ptr) -> ptr { return p }
borrow(el: ptr, t: float) { println("${el == null} ${t}") }
AE
}

{ head_ae; cat <<'AE'
animate(el: @keep ptr, tick: fn(@keep ptr, float)) { tick(el, 0.5) }
build(p: ptr, mk: fn(@into ptr) -> ptr) -> bool {
    q = mk(p)
    return q == p
}
weaker(mk: fn(@keep ptr) -> ptr) -> ptr { return mk(null) }

main() {
    registry = list.new()
    s = list.new()
    animate(s) callback | el: @keep ptr, t: float | { set_fill(el, t) }
    animate(s) callback | el, t | { set_fill(el, t) }
    animate(s, set_fill)
    animate(s, borrow)
    g = set_fill
    animate(s, g)
    let k: fn(@keep ptr, float) = | el: @keep ptr, t: float | { set_fill(el, t) }
    animate(s, k)
    x = 0
    println("${build((&x) as ptr, view)} ${weaker(view) == null}")
    i = | p: @into ptr | { return p }
    println("${build((&x) as ptr, i)}")
}
AE
} > "$TMP/accepted_shapes.ae"
accepted accepted_shapes

# A call through the type is checked by it.
{ head_ae; cat <<'AE'
animate(el: ptr, tick: fn(@keep ptr, float)) {
    tick(el, 0.5)
}

main() { animate(null, set_fill) }
AE
} > "$TMP/borrowed_to_keep.ae"
refused borrowed_to_keep 11:10 E0902 "'el' is a borrowed \`ptr\` parameter, passed to a parameter that keeps it"

{ head_ae; cat <<'AE'
relay(el: ptr) {
    f = set_fill
    call(f, el, 0.5)
}

main() { relay(null) }
AE
} > "$TMP/through_local.ae"
refused through_local 12:13 E0902 "'el' is a borrowed \`ptr\` parameter, passed to a parameter that keeps it"

{ head_ae; cat <<'AE'
tick_text(tick: fn(@keep ptr, float)) {
    s = string.concat("a", string.from_int(1))
    tick(s, 0.5)
}

main() { tick_text(set_fill) }
AE
} > "$TMP/string_to_keep.ae"
refused string_to_keep 12:10 E0902 "a \`string\` is given to a \`@keep ptr\` parameter"

{ head_ae; cat <<'AE'
put(p: ptr, mk: fn(@into ptr) -> ptr) {
    kept = mk(p)
}

main() { put(null, view) }
AE
} > "$TMP/into_escapes.ae"
refused into_escapes 11:5 E0902 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

{ head_ae; cat <<'AE'
main() {
    f = | p: @into ptr | {
        kept = p
        return p
    }
    call(f, null)
}
AE
} > "$TMP/closure_into_kept.ae"
refused closure_into_kept 12:9 E0902 "'p' is an \`@into ptr\` parameter, stored in a module-level \`var\`"

# Never the reverse.
{ head_ae; cat <<'AE'
run(tick: fn) { call(tick, null, 0.5) }

main() {
    registry = list.new()
    run(| el: @keep ptr, t: float | { set_fill(el, t) })
}
AE
} > "$TMP/closure_to_bare.ae"
refused closure_to_bare 14:9 E0902 "the closure keeps its \`ptr\` parameter 1 (\`@keep\`), where \`fn\` borrows it"

{ head_ae; cat <<'AE'
run(tick: fn) { call(tick, null, 0.5) }

main() { run(set_fill) }
AE
} > "$TMP/function_to_bare.ae"
refused function_to_bare 12:14 E0902 "'set_fill' keeps its \`ptr\` parameter 1 (\`@keep\`), where \`fn\` borrows it"

{ head_ae; cat <<'AE'
keeper(p: @keep ptr) -> ptr { return p }
build(mk: fn(@into ptr) -> ptr) -> ptr { return mk(null) }

main() { println("${build(keeper) == null}") }
AE
} > "$TMP/keep_to_into.ae"
refused keep_to_into 13:27 E0902 "'keeper' keeps its \`ptr\` parameter 1 (\`@keep\`), where \`fn(@into ptr) -> ptr\` passes it into its result"

{ head_ae; cat <<'AE'
main() {
    let h: fn = | el: @keep ptr, t: float | { set_fill(el, t) }
    call(h, null, 0.5)
}
AE
} > "$TMP/binding_bare.ae"
refused binding_bare 11:17 E0902 "'h' is \`fn\`, which borrows its \`ptr\` at parameter 1, and the function bound to it keeps its \`ptr\` parameter 1 (\`@keep\`)"

{ head_ae; cat <<'AE'
main() {
    registry = list.new()
    list.add(registry, set_fill)
}
AE
} > "$TMP/into_ptr.ae"
refused into_ptr 12:24 E0902 "'set_fill' keeps its \`ptr\` parameter 1 (\`@keep\`), so it cannot go into a \`ptr\`"

{ head_ae; cat <<'AE'
main() {
    b = box_closure(| el: @keep ptr | { set_fill(el, 0.5) })
    println("${b == null}")
}
AE
} > "$TMP/boxed.ae"
refused boxed 11:21 E0902 "a closure that keeps its \`ptr\` parameter 1 (\`@keep\`) cannot be boxed"

{ head_ae; cat <<'AE'
main() {
    g = set_fill as fn(@keep ptr, float)
    g(null, 0.5)
}
AE
} > "$TMP/cast.ae"
refused cast 11:9 E0902 "\`as fn(...)\` makes a C function pointer, whose parameters borrow"

cat > "$TMP/alias.ae" <<'AE'
type Tick = fn(@keep ptr, float)

main() { println("x") }
AE
refused alias 1:6 E0100 "a function-pointer type alias is a C function pointer, whose parameters borrow"

cat > "$TMP/both.ae" <<'AE'
run(tick: fn(@keep @into ptr)) { call(tick, null) }

main() { println("x") }
AE
refused both 1:14 E0100 "a parameter of a function type is \`@keep\` or \`@into\`, not both"

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] fn_type_modes: @keep and @into in a function type; calls through it checked; never the unsound direction"
