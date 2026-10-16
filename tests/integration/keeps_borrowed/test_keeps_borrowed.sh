#!/bin/sh
# A `ptr` parameter is borrowed for the call unless declared `@keep` (E0902,
# #2926).
#
# A `ptr` slot owns nothing, so a pointer kept there lives only as long as
# its owner: a string a caller passed would be freed under it. Each function
# is checked against its own body: a borrowed `ptr` parameter is not stored
# where it outlives the call, returned, captured, put in a struct or a
# message, or passed to a `@keep` parameter. A call is checked against the
# callee's signature: a `string` reaches a `@keep ptr`, or a `ptr` field,
# only through `string.keep(s)`. A closure's `ptr` parameter is always borrowed, and a
# function with a `@keep` parameter is called by name, never as a value.

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
refused captured 2:12 "'p' is a borrowed \`ptr\` parameter, captured by a closure"

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

cat > "$TMP/keep_as_value.ae" <<'AE'
var kept: ptr = null

hold(p: @keep ptr) {
    kept = p
}

main() {
    f = hold
    call(f, null)
}
AE
refused keep_as_value 8:9 "'hold' keeps its \`ptr\` parameter 'p' (\`@keep\`), so it cannot be used as a value"

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

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] keeps_borrowed: a borrowed ptr parameter is never kept; @keep, string.keep, string.seq_retain and a re-bound parameter are"
