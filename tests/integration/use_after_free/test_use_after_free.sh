#!/bin/sh
# Use after free, double free and dead views are compile errors (#1300).
#
# A local freed on every path that reaches a later use is E0903 there: a
# read, a second free, a free a loop repeats on its next turn, and a read of
# a view (a slice, a cast, the result of an `@into` call) after its storage
# was freed or may have moved. What a call does to its argument is read from
# its declaration (`@frees`, `@moves`, C's free and heap.free), and an
# Aether function's `@frees` and `@moves` are checked against its body
# (E0904). Only faults that happen on every path are reported: the near
# misses at the end must stay quiet.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] use_after_free: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0

expect_error() {  # file, fixed string, label
    out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" check "$1" 2>&1)"
    if ! printf '%s' "$out" | grep -qF -- "$2"; then
        echo "  [FAIL] use_after_free: $3"
        printf '%s\n' "$out" | grep -E "^error|-->" | head -6 | sed 's/^/        /'
        fail=1
    fi
}

expect_count() {  # file, code, count, label
    n="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" check "$1" 2>&1 | grep -c "^error\[$2\]")"
    if [ "$n" != "$3" ]; then
        echo "  [FAIL] use_after_free: $4 ($n, expected $3)"
        (cd "$tmp" && AETHER_HOME="$ROOT" "$AE" check "$1" 2>&1) | grep -E "^error|-->" | head -8 | sed 's/^/        /'
        fail=1
    fi
}

cat > "$tmp/faults.ae" <<'AE'
import std.bytes

extern malloc(n: int) -> ptr

struct Node { v: int }

twice() {
    p = malloc(16)
    free(p)
    free(p)
}

read_after() -> int {
    n = heap.new(Node)
    n.v = 3
    heap.free(n)
    return n.v
}

every_turn(count: int) {
    p = malloc(8)
    i = 0
    while i < count {
        free(p)
        i = i + 1
    }
}

slice_after() -> int {
    buf = make([]int, 4)
    s = buf[1..3]
    free(buf)
    return s[0]
}

cast_after() -> int {
    raw = malloc(8)
    n = raw as *Node
    free(raw)
    return n.v
}

view_after_grow() -> int {
    b = bytes.new(4)
    bytes.set(b, 0, 7)
    v = bytes.view(b)
    bytes.set(b, 100, 1)
    x = v[0]
    bytes.free(b)
    return x
}

buffer_after_free() -> int {
    b = bytes.new(4)
    bytes.free(b)
    return bytes.length(b)
}

main() {
    twice()
}
AE
expect_error faults.ae "error[E0903]: 'p' is freed again: it was freed at line 9" "a second free was not refused"
expect_error faults.ae "faults.ae:10:10" "the second free is not where the error points"
expect_error faults.ae "'n' is used after it was freed at line 16" "a read after heap.free was not refused"
expect_error faults.ae "'p' is freed again: it was freed on the loop's previous turn at line 24" \
    "a free the loop repeats was not refused"
expect_error faults.ae "'s' views the storage of 'buf', which was freed at line 32" \
    "a slice of a freed buffer was not refused"
expect_error faults.ae "'n' views the storage of 'raw', which was freed at line 39" \
    "a cast of a freed pointer was not refused"
expect_error faults.ae "'v' views the storage of 'b', which may have moved at line 47" \
    "a bytes view read after the buffer grew was not refused"
expect_error faults.ae "'b' is used after it was freed at line 55" "a std.bytes buffer read after bytes.free was not refused"
expect_count faults.ae E0903 7 "every fault was not reported once"

# The declarations: a function that says it frees must, on every path.
cat > "$tmp/modes.ae" <<'AE'
extern malloc(n: int) -> ptr

release_it(p: @frees ptr) {
    free(p)
}

release_null_ok(p: @frees ptr) {
    if p == null {
        return
    }
    free(p)
}

sometimes(p: @frees ptr, c: int) {
    if c > 0 {
        free(p)
    }
}

swapped(p: @frees ptr) {
    p = malloc(4)
    free(p)
}

grows(p: @moves ptr) -> int {
    return 1
}

main() {
    q = malloc(4)
    release_it(q)
}
AE
expect_error modes.ae "error[E0904]: 'p' is declared \`@frees\`, but a path reaches here without freeing it" \
    "a @frees function that frees on one path only was not refused"
expect_error modes.ae "'p' is declared \`@frees\`, but it is bound to something else before it is freed" \
    "a @frees function that frees something else was not refused"
expect_error modes.ae "'p' is declared \`@moves\`, but no call here may move or free what it points at" \
    "a @moves function that moves nothing was not refused"
expect_count modes.ae E0904 3 "a @frees function that frees on every path (or finds null) was refused"

# Near misses: nothing here is a fault on every path.
cat > "$tmp/fine.ae" <<'AE'
import std.bytes

extern malloc(n: int) -> ptr

struct Node { v: int }

release_it(p: @frees ptr) {
    free(p)
}

fresh_each_turn(count: int) {
    i = 0
    while i < count {
        p = malloc(8)
        free(p)
        i = i + 1
    }
}

one_branch(c: int) {
    p = malloc(8)
    if c > 0 {
        free(p)
    }
    if c <= 0 {
        free(p)
    }
}

rebound() -> int {
    n = heap.new(Node)
    heap.free(n)
    n = heap.new(Node)
    n.v = 2
    r = n.v
    heap.free(n)
    return r
}

null_after() -> int {
    p = malloc(8)
    free(p)
    if p == null {
        return 1
    }
    return 0
}

view_again() -> int {
    b = bytes.new(4)
    bytes.set(b, 0, 7)
    v = bytes.view(b)
    bytes.set(b, 100, 1)
    v = bytes.view(b)
    x = v[0]
    bytes.free(b)
    return x
}

// An owned slice's own `.len` after `free` is E0906 (slice ownership: the
// free consumes it); a view's `.len` is its own, and stays readable.
slice_len() -> int {
    buf = make([]int, 4)
    s = buf[1..3]
    free(buf)
    return s.len
}

// A view passed beside the buffer it views is read as the call is made,
// before the call may move the buffer (std.bytes' README does this).
self_append() -> int {
    b = bytes.new(4)
    bytes.set(b, 0, 7)
    bytes.set(b, 1, 8)
    v = bytes.view(b)
    bytes.copy_from_slice(b, 2, v)
    n = bytes.length(b)
    bytes.free(b)
    return n
}

through_release() {
    p = malloc(8)
    release_it(p)
    p = malloc(8)
    release_it(p)
}

main() {
    fresh_each_turn(2)
    one_branch(1)
    println(rebound())
    println(null_after())
    println(view_again())
    println(slice_len())
    println(self_append())
    through_release()
}
AE
expect_count fine.ae E0903 0 "a near miss was reported"
got="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run fine.ae 2>&1 | tr -d '\r' | tr '\n' ' ')"
if [ "$got" != "2 0 7 2 4 " ]; then
    echo "  [FAIL] use_after_free: the near misses did not run as written (got '$got')"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "  [PASS] use_after_free: freed values, repeated frees and dead views refused; near misses quiet"
fi
exit $fail
