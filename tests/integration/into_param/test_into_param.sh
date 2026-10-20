#!/bin/sh
# A `ptr` parameter declared `@into` may reach the function's result and
# nowhere else (E0902, #2990; docs/design/ownership-model.md).
#
# In the function, an `@into` parameter is checked as a borrowed one, except
# that a `return` may hand it back: the pointer, a view of it, a struct, a
# tuple part or an optional holding it, a closure capturing it, or another
# `@into` call's result. The result type must be able to hold a pointer, and
# only a bare `ptr` may be `@into`. At a call, the result holds what each
# `@into` argument carries, as a struct local does: it may live in a local,
# be read and be lent to borrowing parameters, and it escapes (returned,
# stored in a module-level `var` or through a pointer, given to a `@keep`
# parameter) only with the argument. Signature-decided: no rule reads
# another function's body.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] into_param: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# refused <name> <line:col> <text>: `ae check` refuses <name>.ae with E0902
# at that position, its message containing <text>.
refused() {
    name="$1"; at="$2"; text="$3"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $name: accepted"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    case "$out" in
        *"error[E0902]"*"$text"*"$name.ae:$at"*) ;;
        *) echo "  [FAIL] $name: not E0902 \"$text\" at $at:"
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

# The worked example of the design: aephysics' query recorder.
cat > "$TMP/recorder.ae" <<'AE'
struct QueryRecorder { context: ptr, count: int, has_overlap: bool, overlap: fn }

query_recorder(context: @into ptr) -> QueryRecorder {
    return QueryRecorder { context: context, count: 0, has_overlap: false,
                           overlap: |x: int| { println("${x}") } }
}

overlap_internal(visitor: fn, context: ptr) -> int {
    return (context as *QueryRecorder).count
}

finish_query(q: *QueryRecorder) -> int { return q.count }

overlap_aabb(visitor: fn, context: ptr) -> int {
    q = query_recorder(context)
    q.overlap = visitor
    q.has_overlap = true
    stats = overlap_internal(visitor, (&q) as ptr)
    finish_query(&q)
    return stats
}

start_query(context: @into ptr) -> QueryRecorder {
    return query_recorder(context)
}

main() {
    x = 0
    println("${overlap_aabb(|i: int| { println("${i}") }, (&x) as ptr)}")
    r = start_query((&x) as ptr)
    println("${r.count}")
}
AE
accepted recorder

cat > "$TMP/results.ae" <<'AE'
struct Node { n: int }

same(p: @into ptr) -> ptr { return p }
view(p: @into ptr) -> *Node { return p as *Node }
tup(p: @into ptr) -> (ptr, int) { return p, 1 }
tup_lit(p: @into ptr) -> (ptr, int) {
    t = (p, 2)
    return t
}
opt(p: @into ptr) -> ptr? { return p }
later(p: @into ptr) -> fn {
    return || { println("${p == null}") }
}
pair(a: @into ptr, b: @into ptr) -> (ptr, ptr) { return a, b }
unreached(p: @into ptr) -> ptr { return null }

reads(p: ptr) -> int { return 1 }

use_all(p: ptr) -> int {
    a = same(p)
    v = view(p)
    x, n = tup(p)
    y, m = tup_lit(p)
    o = opt(p)
    f = later(p)
    call(f)
    l, r = pair(p, a)
    z = o!
    match opt(p) {
        some(w) -> { reads(w) }
        none -> { println("none") }
    }
    if x == y && l == r && z == a { return n + m + v.n + reads(same(p)) }
    if unreached(p) == null { return 0 }
    return 1
}

main() {
    k = heap.new(Node)
    println("${use_all(k)}")
}
AE
accepted results

cat > "$TMP/strings.ae" <<'AE'
import std.string

const LABEL = "pinned"

same(p: @into ptr) -> ptr { return p }

text(w: string) -> ptr {
    s = "${w}!"
    return same(string.keep(s))
}

main() {
    t = text("x")
    a = same("literal")
    b = same(LABEL)
    seq = string.split_to_seq("a,b", ",")
    c = same(string.seq_retain(seq))
    println("${string.equals(t, "x!")} ${a == b}")
    string.release_kept(t)
    string.seq_free(c)
}
AE
accepted strings

cat > "$TMP/c_into.ae" <<'AE'
extern calloc(n: int, size: int) -> ptr
extern free(p: ptr)
extern memchr(s: @into ptr, c: int, n: int) -> ptr

first_seven(buf: ptr) -> int {
    hit = memchr(buf, 7, 8)
    if hit == null { return 0 }
    return 1
}

main() {
    buf = calloc(8, 1)
    println("${first_seven(buf)}")
    free(buf)
}
AE
accepted c_into

# #2979's question is asked of the argument: the result of an `@into` call
# is the argument's memory, so a string local stored through it is fine
# while that memory ends with the function.
cat > "$TMP/c_memory_local.ae" <<'AE'
import std.string

extern calloc(n: int, size: int) -> ptr
extern free(p: ptr)

view(p: @into ptr) -> ptr { return p }

argv(w: string) {
    names = calloc(2, 8)
    v = view(names)
    s = string.concat(w, "b")
    (v as string[])[0] = s
    free(names)
}

main() { argv("a") }
AE
accepted c_memory_local

# In the function: every escape but the result is still E0902.
cat > "$TMP/into_global.ae" <<'AE'
var kept: ptr = null

same(p: @into ptr) -> ptr {
    kept = p
    return p
}

main() { println("${same(null) == null}") }
AE
refused into_global 4:5 "'p' is an \`@into ptr\` parameter, stored in a module-level \`var\`"

# #3033: a pointer computed from the parameter (`p + n`) is a view of it:
# the result may hold it, nothing else may, and at a call the result plus
# an offset still holds the argument.
cat > "$TMP/into_arith_global.ae" <<'AE'
var kept: ptr = null

skip(p: @into ptr) -> ptr {
    kept = p + 4
    return p + 8
}

main() { println("${skip(null) == null}") }
AE
refused into_arith_global 4:5 "'p' is an \`@into ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/into_arith_result.ae" <<'AE'
var kept: ptr = null

skip(p: @into ptr) -> ptr { return p + 8 }

put(p: ptr) {
    q = skip(p) - 2
    kept = q
}

main() { put(null) }
AE
refused into_arith_result 7:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/into_arith_view.ae" <<'AE'
skip(p: @into ptr) -> ptr { return p + 8 }

look(p: ptr) -> int {
    q = skip(p) - 8
    if q == p { return 1 }
    return 0
}

main() {
    x = 0
    println("${look((&x) as ptr)}")
}
AE
accepted into_arith_view

cat > "$TMP/into_field.ae" <<'AE'
struct Holder { h: ptr }

same(n: *Holder, p: @into ptr) -> ptr {
    n.h = p
    return p
}

main() { println("${same(heap.new(Holder), null) == null}") }
AE
refused into_field 4:9 "'p' is an \`@into ptr\` parameter, stored in a field or an element"

cat > "$TMP/into_keep.ae" <<'AE'
var kept: ptr = null

hold(q: @keep ptr) { kept = q }

same(p: @into ptr) -> ptr {
    hold(p)
    return p
}

main() { println("${same(null) == null}") }
AE
refused into_keep 6:10 "'p' is an \`@into ptr\` parameter, passed to a parameter that keeps it"

cat > "$TMP/into_closure_stored.ae" <<'AE'
var on_tick: ptr = null

later(p: @into ptr) -> ptr {
    on_tick = || { println("${p == null}") }
    return p
}

main() { println("${later(null) == null}") }
AE
refused into_closure_stored 4:5 "'p' is an \`@into ptr\` parameter captured by a closure that is stored in a module-level \`var\`"

cat > "$TMP/borrowed_beside_into.ae" <<'AE'
pick(a: @into ptr, b: ptr) -> ptr {
    if a == null { return b }
    return a
}

main() { println("${pick(null, null) == null}") }
AE
refused borrowed_beside_into 2:20 "'b' is a borrowed \`ptr\` parameter, returned"

# The declaration.
cat > "$TMP/result_int.ae" <<'AE'
count(p: @into ptr) -> int { return 1 }

main() { println("${count(null)}") }
AE
refused result_int 1:7 "'p' is declared \`@into\`, but 'count' returns int, which cannot hold it"

cat > "$TMP/result_none.ae" <<'AE'
show(p: @into ptr) { println("${p == null}") }

main() { show(null) }
AE
refused result_none 1:6 "'p' is declared \`@into\`, but 'show' has no result to hold it"

cat > "$TMP/result_string.ae" <<'AE'
name(p: @into ptr) -> string { return "x" }

main() { println(name(null)) }
AE
refused result_string 1:6 "'p' is declared \`@into\`, but 'name' returns string, which cannot hold it"

cat > "$TMP/result_scalars.ae" <<'AE'
struct Counts { a: int, b: string }

tally(p: @into ptr) -> Counts { return Counts { a: 1, b: "x" } }

main() { println("${tally(null).a}") }
AE
refused result_scalars 3:7 "'p' is declared \`@into\`, but 'tally' returns Counts, which cannot hold it"

cat > "$TMP/typed_ptr.ae" <<'AE'
struct Node { n: int }

same(p: @into *Node) -> *Node { return p }

main() { println("${same(heap.new(Node)).n}") }
AE
refused typed_ptr 3:6 "\`@into\` applies to a \`ptr\` parameter; 'p' is a *Node, which E0902 leaves alone"

cat > "$TMP/into_and_keep.ae" <<'AE'
same(p: @keep @into ptr) -> ptr { return p }

main() { println("${same(null) == null}") }
AE
refused into_and_keep 1:6 "'p' is declared both \`@into\` and \`@keep\`"

cat > "$TMP/into_and_retain.ae" <<'AE'
extern c_view(p: @into @retain ptr) -> ptr

main() { println("${c_view(null) == null}") }
AE
refused into_and_retain 1:15 "'p' is declared both \`@into\` and \`@retain\`"

# A closure's parameter may be `@into` too (#2980), and is held to the same
# rule: here no result can hold it.
cat > "$TMP/closure_param.ae" <<'AE'
main() {
    f = |p: @into ptr| { println("${p == null}") }
    call(f, null)
}
AE
refused closure_param 2:10 "'p' is declared \`@into\`, but the closure has no result to hold it"

# A function with an `@into` parameter is a value of a type that says so
# (#2980): a call through it is checked as a direct call is.
cat > "$TMP/as_value.ae" <<'AE'
var kept: ptr = null

same(p: @into ptr) -> ptr { return p }

relay(p: ptr) {
    f = same
    kept = f(p)
}

main() { relay(null) }
AE
refused as_value 7:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/as_fn_pointer.ae" <<'AE'
same(p: @into ptr) -> ptr { return p }

main() {
    g = same as fn(ptr) -> ptr
    println("${g(null) == null}")
}
AE
refused as_fn_pointer 4:9 "'same' passes its \`ptr\` parameter 'p' into its result (\`@into\`), so it cannot be a C function pointer"

# At a call: the result holds the argument, and escapes with it.
cat > "$TMP/result_global.ae" <<'AE'
struct QueryRecorder { context: ptr, count: int }

var last_query: QueryRecorder = QueryRecorder { context: null, count: 0 }

query_recorder(context: @into ptr) -> QueryRecorder {
    return QueryRecorder { context: context, count: 0 }
}

overlap(context: ptr) {
    q = query_recorder(context)
    last_query = q
}

main() { overlap(null) }
AE
refused result_global 11:5 "'context' is a borrowed \`ptr\` parameter held by the result of 'query_recorder' that is stored in a module-level \`var\`"

cat > "$TMP/result_returned.ae" <<'AE'
struct QueryRecorder { context: ptr, count: int }

query_recorder(context: @into ptr) -> QueryRecorder {
    return QueryRecorder { context: context, count: 0 }
}

start_query(context: ptr) -> QueryRecorder {
    return query_recorder(context)
}

main() { println("${start_query(null).count}") }
AE
refused result_returned 8:12 "'context' is a borrowed \`ptr\` parameter held by the result of 'query_recorder' that is returned"

cat > "$TMP/result_to_keep.ae" <<'AE'
struct QueryRecorder { context: ptr, count: int }

var world: ptr = null

hold(q: @keep ptr) { world = q }

query_recorder(context: @into ptr) -> QueryRecorder {
    return QueryRecorder { context: context, count: 0 }
}

overlap(context: ptr) {
    q = query_recorder(context)
    hold((&q) as ptr)
}

main() { overlap(null) }
AE
refused result_to_keep 13:15 "'context' is a borrowed \`ptr\` parameter held by the result of 'query_recorder' that is passed to a parameter that keeps it"

cat > "$TMP/pointer_result_global.ae" <<'AE'
var kept: ptr = null

same(p: @into ptr) -> ptr { return p }

put(p: ptr) {
    kept = same(p)
}

main() { put(null) }
AE
refused pointer_result_global 6:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/in_place.ae" <<'AE'
var kept: ptr = null

hold(q: @keep ptr) { kept = q }
same(p: @into ptr) -> ptr { return p }

put(p: ptr) {
    hold(same(same(p)))
}

main() { put(null) }
AE
refused in_place 7:10 "'p' is a borrowed \`ptr\` parameter, passed to a parameter that keeps it"

cat > "$TMP/chain_global.ae" <<'AE'
struct QueryRecorder { context: ptr, count: int }

var last_query: QueryRecorder = QueryRecorder { context: null, count: 0 }

query_recorder(context: @into ptr) -> QueryRecorder {
    return QueryRecorder { context: context, count: 0 }
}

start_query(context: @into ptr) -> QueryRecorder {
    return query_recorder(context)
}

overlap(context: ptr) {
    last_query = start_query(context)
}

main() { overlap(null) }
AE
refused chain_global 14:5 "'context' is a borrowed \`ptr\` parameter held by the result of 'start_query' that is stored in a module-level \`var\`"

cat > "$TMP/several.ae" <<'AE'
var kept: ptr = null

pick(a: @into ptr, b: @into ptr) -> ptr {
    if a == null { return b }
    return a
}

put(x: ptr, y: ptr) {
    kept = pick(x, y)
}

main() { put(null, null) }
AE
refused several 9:5 "'x' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"
refused several 9:5 "'y' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/part_global.ae" <<'AE'
var kept: ptr = null

tup(p: @into ptr) -> (ptr, int) { return p, 1 }

put(p: ptr) {
    x, n = tup(p)
    kept = x
}

main() { put(null) }
AE
refused part_global 7:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/payload_global.ae" <<'AE'
var kept: ptr = null

opt(p: @into ptr) -> ptr? { return p }

put(p: ptr) {
    o = opt(p)
    kept = o!
}

main() { put(null) }
AE
refused payload_global 7:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/binding_global.ae" <<'AE'
var kept: ptr = null

opt(p: @into ptr) -> ptr? { return p }

put(p: ptr) {
    match opt(p) {
        some(v) -> { kept = v }
        none -> { println("none") }
    }
}

main() { put(null) }
AE
refused binding_global 7:22 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/string_implicit.ae" <<'AE'
import std.string

same(p: @into ptr) -> ptr { return p }

main() {
    s = string.concat("a", string.from_int(1))
    t = same(s)
    println("${t == null}")
}
AE
refused string_implicit 7:14 "a \`string\` is given to an \`@into ptr\` parameter, and the result holds it past the call"

cat > "$TMP/c_memory_escape.ae" <<'AE'
import std.string

extern calloc(n: int, size: int) -> ptr

view(p: @into ptr) -> ptr { return p }

argv(w: string) -> ptr {
    names = calloc(2, 8)
    v = view(names)
    s = string.concat(w, "b")
    (v as string[])[0] = s
    return v
}

main() { println("${argv("a") == null}") }
AE
refused c_memory_escape 11:26 "a string is stored into C memory that outlives the function"

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] into_param: an @into ptr reaches only the result; the caller holds the result as a local, and it escapes only with the argument"
