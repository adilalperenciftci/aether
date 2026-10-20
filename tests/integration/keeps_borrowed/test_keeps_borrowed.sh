#!/bin/sh
# A `ptr` parameter is borrowed for the call unless declared `@keep` (E0902,
# #2926).
#
# A `ptr` slot owns nothing, so a pointer kept there lives only as long as
# its owner: a string a caller passed would be freed under it. Each function
# is checked against its own body: a borrowed `ptr` parameter is not stored
# where it outlives the call, returned, sent in a message, or passed to a
# `@keep` parameter. A struct local to the function, and a closure that runs
# and is dropped inside the call, do not outlive it: putting the parameter in
# one is a keep only when the struct or the closure escapes itself (returned,
# stored in a field, a module-level `var` or a container, or passed to a
# `@keep` or `@retain` parameter). A call is checked against the
# callee's signature: a `string` reaches a `@keep ptr`, or a `ptr` field,
# only through `string.keep(s)`. A function with a `@keep` parameter is no typed C
# function pointer, and as a value it goes only where its type says it keeps (#2980).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] keeps_borrowed: ae not built"; exit 0; }

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

cat > "$TMP/field.ae" <<'AE'
struct Node { child: ptr }

attach(n: *Node, c: ptr) {
    n.child = c
}

main() { attach(heap.new(Node), null) }
AE
refused field 4:13 "'c' is a borrowed \`ptr\` parameter, stored in a field or an element"

cat > "$TMP/returned.ae" <<'AE'
same(p: ptr) -> ptr {
    return p
}

main() { println("${same(null) == null}") }
AE
refused returned 2:5 "'p' is a borrowed \`ptr\` parameter, returned"

cat > "$TMP/global.ae" <<'AE'
var last: ptr = null

remember(p: ptr) {
    q = p
    last = q
}

main() { remember(null) }
AE
refused global 5:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/captured.ae" <<'AE'
later(p: ptr) -> fn {
    return || { println("${p == null}") }
}

main() { call(later(null)) }
AE
refused captured 2:12 "'p' is a borrowed \`ptr\` parameter captured by a closure that is returned"

cat > "$TMP/passed_on.ae" <<'AE'
var kept: ptr = null

hold(p: @keep ptr) {
    kept = p
}

relay(p: ptr) {
    hold(p)
}

main() { relay(null) }
AE
refused passed_on 8:10 "'p' is a borrowed \`ptr\` parameter, passed to a parameter that keeps it"

cat > "$TMP/closure_param.ae" <<'AE'
var kept: ptr = null

main() {
    f = |p: ptr| { kept = p }
    call(f, null)
}
AE
refused closure_param 4:20 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/string_to_keep.ae" <<'AE'
var kept: ptr = null

hold(p: @keep ptr) {
    kept = p
}

main() {
    s = "text"
    hold(s)
}
AE
refused string_to_keep 9:10 "a \`string\` is given to a \`@keep ptr\` parameter"

# A function with a `@keep` parameter is a value of a type that says so
# (#2980): it may not go where a call through it would be checked as one
# that borrows, a bare `fn` here.
cat > "$TMP/keep_as_value.ae" <<'AE'
var kept: ptr = null

hold(p: @keep ptr) {
    kept = p
}

run(cb: fn) { call(cb, null) }

main() {
    f = hold
    run(f)
}
AE
refused keep_as_value 11:9 "'f' keeps its \`ptr\` parameter 1 (\`@keep\`), where \`fn\` borrows it"

cat > "$TMP/string_field.ae" <<'AE'
struct N { child: ptr }

put(n: *N, s: string) {
    n.child = s
}

main() { put(heap.new(N), "x") }
AE
refused string_field 4:15 "a \`string\` is given to a \`ptr\` field"

cat > "$TMP/string_literal_field.ae" <<'AE'
struct N { child: ptr }

mk(s: string) -> N {
    return N { child: s }
}

main() { n = mk("x") }
AE
refused string_literal_field 4:23 "a \`string\` is given to a \`ptr\` field"

cat > "$TMP/seq_to_keep.ae" <<'AE'
import std.string

var kept: ptr = null

hold(p: @keep ptr) {
    kept = p
}

main() {
    s = string.split_to_seq("a,b", ",")
    hold(s)
}
AE
refused seq_to_keep 11:10 "a \`*StringSeq\` is given to a \`@keep ptr\` parameter"

cat > "$TMP/seq_field.ae" <<'AE'
import std.string

struct N { child: ptr }

put(n: *N, s: *StringSeq) {
    n.child = s
}

main() { put(heap.new(N), string.split_to_seq("a,b", ",")) }
AE
refused seq_field 6:15 "a \`*StringSeq\` is given to a \`ptr\` field"

cat > "$TMP/c_view_temp.ae" <<'AE'
import std.string

extern calloc(n: int, size: int) -> ptr

main() {
    names = calloc(2, 8)
    (names as string[])[0] = string.concat("a", string.from_int(1))
}
AE
refused c_view_temp 7:36 "a string built here is stored into C memory"

cat > "$TMP/declared.ae" <<'AE'
import std.string

struct Node { child: ptr, n: int }
var kept: ptr = null

attach(n: *Node, c: @keep ptr) {
    n.child = c
}

hold(p: @keep ptr) {
    kept = p
}

read(p: ptr, n: *Node) -> int {
    q = heap.new(Node)
    q.n = n.n
    p = q
    kept = p
    return n.n
}

main() {
    n = heap.new(Node)
    attach(n, null)
    hold(string.keep("text"))
    println("${read(null, n)}")
    string.release_kept(kept)
    seq = string.split_to_seq("a,b", ",")
    hold(string.seq_retain(seq))
    string.seq_free(kept)
}
AE
accepted declared

# A `const` bound to a literal is pinned, as the literal is.
cat > "$TMP/keep_const.ae" <<'AE'
const LABEL = "job"

var kept: ptr = null

hold(p: @keep ptr) {
    kept = p
}

main() { hold(LABEL) }
AE
accepted keep_const

# A struct or a closure that holds a borrowed parameter keeps it only when
# it escapes itself (Nic, 2026-10-19): each escaping form is still E0902.

cat > "$TMP/struct_returned.ae" <<'AE'
struct Pair { a: ptr, b: int }

wrap(p: ptr) -> Pair {
    s = Pair { a: p, b: 1 }
    return s
}

main() { println("${wrap(null).b}") }
AE
refused struct_returned 5:12 "'p' is a borrowed \`ptr\` parameter held by a struct that is returned"

cat > "$TMP/struct_lit_returned.ae" <<'AE'
struct Pair { a: ptr, b: int }

wrap(p: ptr) -> Pair {
    return Pair { a: p, b: 1 }
}

main() { println("${wrap(null).b}") }
AE
refused struct_lit_returned 4:12 "'p' is a borrowed \`ptr\` parameter held by a struct that is returned"

cat > "$TMP/struct_in_field.ae" <<'AE'
struct Pair { a: ptr, b: int }
struct Holder { pair: Pair }

put(h: *Holder, p: ptr) {
    s = Pair { a: p, b: 1 }
    h.pair = s
}

main() { put(heap.new(Holder), null) }
AE
refused struct_in_field 6:12 "'p' is a borrowed \`ptr\` parameter held by a struct that is stored in a field or an element"

cat > "$TMP/struct_in_global.ae" <<'AE'
struct Pair { a: ptr, b: int }
var last: Pair = Pair { a: null, b: 0 }

put(p: ptr) {
    s = Pair { a: p, b: 1 }
    last = s
}

main() { put(null) }
AE
refused struct_in_global 6:5 "'p' is a borrowed \`ptr\` parameter held by a struct that is stored in a module-level \`var\`"

cat > "$TMP/struct_field_read_escapes.ae" <<'AE'
struct Pair { a: ptr, b: int }
var kept: ptr = null

put(p: ptr) {
    s = Pair { a: p, b: 1 }
    kept = s.a
}

main() { put(null) }
AE
refused struct_field_read_escapes 6:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/struct_to_keep.ae" <<'AE'
struct Pair { a: ptr, b: int }
var kept: ptr = null

hold(q: @keep ptr) { kept = q }

put(p: ptr) {
    s = Pair { a: p, b: 1 }
    hold(&s)
}

main() { put(null) }
AE
refused struct_to_keep 8:10 "'p' is a borrowed \`ptr\` parameter held by a struct that is passed to a parameter that keeps it"

cat > "$TMP/closure_local_returned.ae" <<'AE'
later(p: ptr) -> fn {
    f = || { println("${p == null}") }
    return f
}

main() { call(later(null)) }
AE
refused closure_local_returned 3:12 "'p' is a borrowed \`ptr\` parameter captured by a closure that is returned"

cat > "$TMP/closure_in_field.ae" <<'AE'
struct Holder { cb: fn }

put(h: *Holder, p: ptr) {
    h.cb = || { println("${p == null}") }
}

main() { put(heap.new(Holder), null) }
AE
refused closure_in_field 4:10 "'p' is a borrowed \`ptr\` parameter captured by a closure that is stored in a field or an element"

cat > "$TMP/closure_in_global.ae" <<'AE'
var on_tick: ptr = null

put(p: ptr) {
    on_tick = || { println("${p == null}") }
}

main() { put(null) }
AE
refused closure_in_global 4:5 "'p' is a borrowed \`ptr\` parameter captured by a closure that is stored in a module-level \`var\`"

cat > "$TMP/closure_in_container.ae" <<'AE'
import std.list

put(l: ptr, p: ptr) {
    f = || { println("${p == null}") }
    list.add(l, f)
}

main() { put(list.new(), null) }
AE
refused closure_in_container 5:17 "'p' is a borrowed \`ptr\` parameter captured by a closure that is stored in a container"

cat > "$TMP/closure_to_keep.ae" <<'AE'
var kept: ptr = null

hold(f: @keep fn) { kept = f }

put(p: ptr) {
    hold(|| { println("${p == null}") })
}

main() { put(null) }
AE
refused closure_to_keep 6:10 "'p' is a borrowed \`ptr\` parameter captured by a closure that is passed to a parameter that keeps it"

cat > "$TMP/closure_to_retain.ae" <<'AE'
extern c_register(f: @retain fn)

put(p: ptr) {
    c_register(|| { println("${p == null}") })
}

main() { put(null) }
AE
refused closure_to_retain 4:16 "'p' is a borrowed \`ptr\` parameter captured by a closure that is passed to a parameter that keeps it"

cat > "$TMP/closure_stores_inside.ae" <<'AE'
var kept: ptr = null

run(cb: fn) { cb() }

put(p: ptr) {
    run(|| { kept = p })
}

main() { put(null) }
AE
refused closure_stores_inside 6:14 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

# A tuple, an optional's payload, a match binding and what a closure that
# captured the parameter returns hold it as a struct does (#2990): each
# escaping form is E0902.

cat > "$TMP/tuple_returned.ae" <<'AE'
wrap(p: ptr) -> (ptr, int) {
    t = (p, 1)
    return t
}

main() {
    a, b = wrap(null)
    println("${a == null} ${b}")
}
AE
refused tuple_returned 3:12 "'p' is a borrowed \`ptr\` parameter held by a tuple that is returned"

cat > "$TMP/tuple_part_global.ae" <<'AE'
var kept: ptr = null

put(p: ptr) {
    t = (p, 1)
    a, b = t
    kept = a
    println("${b}")
}

main() { put(null) }
AE
refused tuple_part_global 6:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

# #2990: a part read out of a tuple local holds what that part holds, and no
# more: the other part here is a block of the function's own.
cat > "$TMP/tuple_other_part.ae" <<'AE'
extern malloc(n: int) -> ptr
extern free(p: ptr)

second(p: ptr) -> ptr {
    t = (p, malloc(8))
    a, b = t
    if a == null { free(b) }
    return b
}

main() {
    q = malloc(4)
    free(second(q))
    free(q)
}
AE
accepted tuple_other_part

cat > "$TMP/tuple_nested_part.ae" <<'AE'
extern malloc(n: int) -> ptr

var kept: ptr = null

put(p: ptr) -> ptr {
    t = ((1, p), malloc(8))
    x, y = t
    n, q = x
    kept = q
    return y
}

main() { println("${put(null) == null}") }
AE
refused tuple_nested_part 9:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/tuple_nested_other.ae" <<'AE'
extern malloc(n: int) -> ptr
extern free(p: ptr)

second(p: ptr) -> ptr {
    t = ((1, p), malloc(8))
    x, y = t
    n, q = x
    if q == null { return y }
    return y
}

main() { free(second(null)) }
AE
accepted tuple_nested_other

# #3036: a field read out of a struct local holds what went into that field,
# by the literal, by a store into it, nested, or bound by a struct pattern.
cat > "$TMP/struct_other_field.ae" <<'AE'
extern malloc(n: int) -> ptr
extern free(p: ptr)

struct Pair { a: ptr, b: ptr }
struct Outer { inner: Pair, n: int }

by_literal(p: ptr) -> ptr {
    s = Pair { a: p, b: malloc(8) }
    if s.a == null { return s.b }
    return s.b
}

by_store(p: ptr) -> ptr {
    s = Pair { a: null, b: null }
    s.a = p
    s.b = malloc(8)
    return s.b
}

nested(p: ptr) -> ptr {
    o = Outer { inner: Pair { a: p, b: malloc(8) }, n: 1 }
    o.inner.a = p
    return o.inner.b
}

by_pattern(p: ptr) -> ptr {
    s = Pair { a: p, b: malloc(8) }
    match s {
        Pair { a: _, b: q } -> { return q }
    }
    return null
}

main() {
    free(by_literal(null))
    free(by_store(null))
    free(nested(null))
    free(by_pattern(null))
}
AE
accepted struct_other_field

cat > "$TMP/struct_nested_field.ae" <<'AE'
struct Pair { a: ptr, b: ptr }
struct Outer { inner: Pair, n: int }

var kept: ptr = null

put(p: ptr) {
    o = Outer { inner: Pair { a: null, b: null }, n: 1 }
    o.inner.b = p
    kept = o.inner.b
}

main() { put(null) }
AE
refused struct_nested_field 9:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

# #3033: `p + n` and `p - n` point into the memory `p` does: stored,
# returned or kept, each is the parameter kept.
cat > "$TMP/arith_global.ae" <<'AE'
var kept: ptr = null

put(p: ptr) {
    kept = p + 8
}

main() { put(null) }
AE
refused arith_global 4:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

cat > "$TMP/arith_returned.ae" <<'AE'
next(p: ptr) -> ptr {
    q = p - 1
    return q + 2
}

main() { println("${next(null) == null}") }
AE
refused arith_returned 3:5 "'p' is a borrowed \`ptr\` parameter, returned"

cat > "$TMP/arith_field.ae" <<'AE'
struct Node { child: ptr }

attach(n: *Node, c: ptr) {
    n.child = c + 16
}

main() { attach(heap.new(Node), null) }
AE
refused arith_field 4:13 "'c' is a borrowed \`ptr\` parameter, stored in a field or an element"

cat > "$TMP/payload_returned.ae" <<'AE'
unwrap(p: ptr) -> ptr {
    let o: ptr? = p
    return o!
}

main() { println("${unwrap(null) == null}") }
AE
refused payload_returned 3:5 "'p' is a borrowed \`ptr\` parameter, returned"

cat > "$TMP/binding_returned.ae" <<'AE'
struct Box { v: ptr, n: int }

unbox(p: ptr) -> ptr {
    b = Box { v: p, n: 1 }
    match b {
        Box { v: q, n: _ } -> { return q }
    }
    return null
}

main() { println("${unbox(null) == null}") }
AE
refused binding_returned 6:33 "'p' is a borrowed \`ptr\` parameter, returned"

cat > "$TMP/closure_result_global.ae" <<'AE'
var kept: ptr = null

leak(p: ptr) {
    f = || { return p }
    let q: ptr = call(f)
    kept = q
}

main() { leak(null) }
AE
refused closure_result_global 6:5 "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"

# A function with a `@keep` parameter is called by name: a typed function
# pointer to it (a cast, a module-level `var`, an argument) would be called
# as one that borrows.

cat > "$TMP/keep_fn_cast.ae" <<'AE'
var kept: ptr = null

hold(q: @keep ptr) { kept = q }

main() {
    g = hold as fn(ptr)
    g(null)
}
AE
refused keep_fn_cast 6:9 "'hold' keeps its \`ptr\` parameter 'q' (\`@keep\`), so it cannot be a C function pointer"

cat > "$TMP/keep_fn_var.ae" <<'AE'
var kept: ptr = null

hold(q: @keep ptr) { kept = q }

var g: fn(ptr) = hold

main() { g(null) }
AE
refused keep_fn_var 5:18 "'hold' keeps its \`ptr\` parameter 'q' (\`@keep\`), so it cannot be a C function pointer"

cat > "$TMP/keep_fn_arg.ae" <<'AE'
var kept: ptr = null

hold(q: @keep ptr) { kept = q }

run(cb: fn(ptr), p: ptr) { cb(p) }

main() { run(hold, null) }
AE
refused keep_fn_arg 7:14 "'hold' keeps its \`ptr\` parameter 'q' (\`@keep\`), so it cannot be a C function pointer"

# Need no `@keep`: the aephysics shape (a struct local to the function holds
# the parameter, or has it stored into a field, and dies with the call) and
# the aeb shape (a closure that captures it runs inside the call and is
# dropped there).

cat > "$TMP/struct_local.ae" <<'AE'
import std.list

struct Pair { a: ptr, b: int }

first(p: ptr) -> int {
    s = Pair { a: p, b: 1 }
    return s.b
}

main() {
    x = list.new()
    println("${first(x)}")
}
AE
accepted struct_local

cat > "$TMP/struct_field_store.ae" <<'AE'
struct Pair { a: ptr, b: int }
struct Job { p: ptr, n: int }

reads(j: *Job) -> int { return j.n }

second(p: ptr, n: int) -> int {
    s = Pair { a: null, b: 2 }
    s.a = p
    job = Job { p: p, n: n }
    if s.a == null { return reads(&job) }
    return s.b + reads(&job)
}

main() { println("${second(null, 3)}") }
AE
accepted struct_field_store

cat > "$TMP/closure_sync.ae" <<'AE'
import std.list

run(cb: fn) { cb() }

count_into(dst: ptr) {
    run(|| { list.add(dst, "x") })
    f = || { list.add(dst, "y") }
    call(f)
    run(f)
}

main() {
    l = list.new()
    count_into(l)
    println("${list.size(l)}")
}
AE
accepted closure_sync

# #2977: a struct local whose address goes only to a borrowing parameter,
# `@scoped` or not.
cat > "$TMP/struct_addr_borrowed.ae" <<'AE'
struct Holder {
    p: ptr
    n: int
}

reads(h: ptr) -> int {
    return (h as *Holder).n
}

look(own: ptr) -> int {
    @scoped h = Holder { p: own, n: 7 }
    return reads((&h) as ptr)
}

look2(own: ptr) -> int {
    h = Holder { p: own, n: 8 }
    return reads((&h) as ptr)
}

main() {
    x = 0
    println("${look((&x) as ptr)} ${look2((&x) as ptr)}")
}
AE
accepted struct_addr_borrowed

# A `ptr` returned at a `string` position is taken as a string: the return
# hands the caller a reference of its own, so the pointer is not kept.
cat > "$TMP/returned_as_string.ae" <<'AE'
as_text(p: ptr) -> string {
    return p
}

pair(p: ptr) -> (string, int) {
    return p, 1
}

main() {
    s, n = pair("b")
    println("${as_text("a")}${s}${n}")
}
AE
accepted returned_as_string

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] keeps_borrowed: a borrowed ptr parameter is never kept, alone or in a struct or closure that escapes; @keep, string.keep, string.seq_retain, a re-bound parameter, a struct local and a closure run in the call are"
