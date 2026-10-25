#!/bin/sh
# Regression: #2975 `move` hands a buffer over. The compiler must REJECT a
# use of the moved-from name after the move (straight line, after an `if`
# arm, in a loop, in a `defer`, in a closure), naming the line that moved it.
# It must also refuse a move it cannot make good on: a borrowed parameter, a
# capture, a field, an element, or a value that is not a `ptr`. And it must
# ACCEPT everything else spelled `move`, because the word is contextual:
# std.fs and std.mem export functions called `move`, and downstream code
# calls them bare after a glob import. Fixtures are inline, so the generic .ae
# runner has nothing to pick up here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

fail() { echo "  [FAIL] buffer_move_reject: $1"; exit 1; }

# expect_reject <name> <source> <pattern>: the build fails, saying <pattern>.
expect_reject() {
    name="$1"; src="$2"; pattern="$3"
    printf '%s\n' "$src" > "$WORK/$name.ae"
    out="$("$AE" build "$WORK/$name.ae" -o "$WORK/$name" 2>&1)"
    if [ $? -eq 0 ]; then fail "$name: expected rejection, but it compiled"; fi
    printf '%s\n' "$out" | grep -qF "$pattern" \
        || fail "$name: rejected, but not with '$pattern'. Got: $(printf '%s' "$out" | grep -i error | head -1)"
}

# expect_accept <name> <source>: the build succeeds.
expect_accept() {
    name="$1"; src="$2"
    printf '%s\n' "$src" > "$WORK/$name.ae"
    if ! "$AE" build "$WORK/$name.ae" -o "$WORK/$name" >"$WORK/$name.log" 2>&1; then
        echo "  [FAIL] buffer_move_reject: $name: expected accept, but it failed:"
        grep -i error "$WORK/$name.log" | head -3
        exit 1
    fi
}

# Every fixture opens with a blank line, then this preamble on lines 2-4, so
# `main() {` is line 5 and its first statement line 6.
PRE='
import std.bytes
message Chunk { data: ptr }
actor Receiver { receive { Chunk(data) -> { bytes.free(data) } } }'

# --- use after the move ---

expect_reject straight_line "$PRE
main() {
    r = spawn(Receiver())
    b = bytes.new(10)
    r ! Chunk { data: move b }
    n = bytes.length(b)
}" "use of moved value 'b': line 8 moved it"

expect_reject if_arm "$PRE
main() {
    r = spawn(Receiver())
    b = bytes.new(10)
    if bytes.length(b) == 0 {
        r ! Chunk { data: move b }
    }
    n = bytes.length(b)
}" "use of moved value 'b': line 9 moved it"

expect_reject loop "$PRE
main() {
    r = spawn(Receiver())
    b = bytes.new(10)
    i = 0
    while i < 2 {
        r ! Chunk { data: move b }
        i = i + 1
    }
}" "use of moved value 'b': line 10 moved it"

expect_reject defer_after "$PRE
main() {
    r = spawn(Receiver())
    b = bytes.new(10)
    defer bytes.free(b)
    r ! Chunk { data: move b }
}" "use of moved value 'b': line 9 moved it"

expect_reject closure_after "$PRE
main() {
    r = spawn(Receiver())
    b = bytes.new(10)
    r ! Chunk { data: move b }
    f = || { println(\"\${bytes.length(b)}\") }
}" "use of moved value 'b': line 8 moved it"

expect_reject move_twice "$PRE
main() {
    r = spawn(Receiver())
    b = bytes.new(10)
    r ! Chunk { data: move b }
    r ! Chunk { data: move b }
}" "use of moved value 'b': line 8 moved it"

# --- moves that are refused ---

expect_reject borrowed_param "$PRE
hand_over(r: ptr, b: ptr) {
    r ! Chunk { data: move b }
}
main() { }" "cannot move borrowed parameter 'b'"

expect_reject captured "$PRE
main() {
    r = spawn(Receiver())
    b = bytes.new(10)
    f = || { r ! Chunk { data: move b } }
}" "cannot move captured variable 'b'"

expect_reject field "$PRE
struct Box { b: ptr }
main() {
    r = spawn(Receiver())
    box = Box { b: bytes.new(10) }
    r ! Chunk { data: move box.b }
}" "cannot move field 'b' out of object 'box'"

expect_reject string_operand '
message Note { s: string }
actor Sink { receive { Note(s) -> { } } }
main() {
    r = spawn(Sink())
    s = "hello"
    r ! Note { s: move s }
}' 'hands over a `ptr` buffer'

expect_reject int_operand '
main() {
    n = 3
    m = move n
}' 'hands over a `ptr` buffer'

# --- accepted ---

expect_accept rebind "$PRE
main() {
    r = spawn(Receiver())
    b = bytes.new(10)
    r ! Chunk { data: move b }
    b = bytes.new(20)
    r ! Chunk { data: move b }
    wait_for_idle()
}"

expect_accept both_arms "$PRE
main() {
    r = spawn(Receiver())
    b = bytes.new(10)
    if bytes.length(b) == 0 {
        r ! Chunk { data: move b }
    } else {
        r ! Chunk { data: move b }
    }
    wait_for_idle()
}"

expect_accept defer_before_unrelated "$PRE
main() {
    r = spawn(Receiver())
    keep = bytes.new(4)
    defer bytes.free(keep)
    b = bytes.new(10)
    r ! Chunk { data: move b }
    wait_for_idle()
}"

expect_accept keep_param "$PRE
hand_over(r: ptr, b: @keep ptr) {
    r ! Chunk { data: move b }
}
main() {
    r = spawn(Receiver())
    hand_over(r, bytes.new(10))
    wait_for_idle()
}"

expect_accept glob_mem_move '
import std.bytes
import std.mem (*)
main() {
    a = bytes.new(4)
    bytes.set(a, 3, 7)
    c = bytes.new(4)
    bytes.set(c, 3, 0)
    move(bytes.data(c), bytes.data(a), 4)
    bytes.free(a)
    bytes.free(c)
}'

expect_accept qualified_fs_move '
import std.fs
main() {
    ok, kind, msg = fs.move("/nonexistent/a", "/nonexistent/b")
    println("${ok} ${kind} ${msg}")
}'

expect_accept name_called_move '
main() {
    move = 3
    total = move + 1
    println("${total}")
}'

# The defer runs where its block ends, not where it is written: consuming an
# Isolated value there is its one use, not a second one.
expect_accept isolated_defer '
take(it: Isolated[int]) -> int { return consume(it) }
main() {
    it = isolate(7)
    defer take(it)
    println("deferred")
}'

echo "  [PASS] buffer_move_reject: uses after a move and refused moves are rejected, the rest accepted"
exit 0
