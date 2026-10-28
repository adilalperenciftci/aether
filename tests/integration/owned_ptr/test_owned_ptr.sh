#!/bin/sh
# An owned pointer has one owner at a time (#3142).
#
# `type Buf = owned ptr drop f` makes a pointer that its holder releases
# with `f` when it lets go. The checker keeps it to one holder: a copy into
# a second place, a free or a keep behind the owner's back, a place that
# could not release it (a struct field, a closure's capture, an optional
# owned value), a `move` into a function (which borrows) and a hand-on of a
# borrowed parameter are each E0905. A use after a `move` is the move
# checker's error. The drop function must free what it is given. What
# stays legal: lending it to a function, returning a local, moving it into
# a message.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] owned_ptr: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0

expect_error() {  # file, fixed string, label
    out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" check "$1" 2>&1)"
    if ! printf '%s' "$out" | grep -qF -- "$2"; then
        echo "  [FAIL] owned_ptr: $3"
        printf '%s\n' "$out" | grep -E "^error|-->" | head -6 | sed 's/^/        /'
        fail=1
    fi
}

head='import std.bytes
import std.list

type Buf = owned ptr drop bytes.free

message Chunk { data: Buf }

actor Sink {
    receive {
        Chunk(data) -> { println(bytes.length(data)) }
    }
}

fill(n: int) -> Buf {
    b = bytes.new(n)
    bytes.set(b, n - 1, 1)
    return b as Buf
}

lend(p: ptr) -> int {
    return bytes.length(p)
}
'

case_file() {  # name, body
    printf '%s\n%s\n' "$head" "$2" > "$tmp/$1.ae"
}

case_file copy 'main() {
    b = fill(1)
    c = b
    println(lend(c))
}'
expect_error copy.ae "error[E0905]: 'c' would be a second owner of what b holds" "a copy was not refused"
expect_error copy.ae "hand it over with \`move\`" "the copy's help does not say move"

case_file freed 'main() {
    b = fill(1)
    bytes.free(b)
}'
expect_error freed.ae "an owned value is released by its owner, so 'bytes.free' must not free it" \
    "a free of an owned value was not refused"

case_file freed_cast 'main() {
    b = fill(1)
    bytes.free(b as ptr)
}'
expect_error freed_cast.ae "must not free it: it would be freed twice" \
    "a free through a cast was not refused"

case_file kept 'main() {
    b = fill(1)
    l = list.new()
    list.add(l, b)
}'
expect_error kept.ae "keeps what it is given, and an owned value has one owner" \
    "a store into a container was not refused"

case_file field 'struct Holder { b: Buf }
main() {
    println("x")
}'
expect_error field.ae "an owned value is not a struct field" "an owned struct field was not refused"

case_file captured 'main() {
    b = fill(1)
    f = || { println(lend(b)) }
    f()
}'
expect_error captured.ae "a closure names the owned value 'b'" "a closure capture was not refused"

case_file optional 'actor Keeper {
    state kept: Buf? = none
    receive {
        Chunk(data) -> { println(lend(data)) }
    }
}
main() {
    println("x")
}'
expect_error optional.ae "kept is an optional owned pointer" "an optional owned value was not refused"

case_file move_arg 'main() {
    b = fill(1)
    println(lend(move b))
}'
expect_error move_arg.ae "'lend' borrows its arguments: an owned value goes to it as it is, not moved" \
    "a move into a function argument was not refused"

case_file unmoved 'main() {
    s = spawn(Sink())
    b = fill(1)
    s ! Chunk { data: b }
    wait_for_idle()
}'
expect_error unmoved.ae "the message takes 'data' from its owner: hand it over with \`move\`" \
    "a message field without move was not refused"

case_file borrowed 'keep_it(b: Buf) -> Buf {
    return b
}
rebind(b: Buf) {
    b = fill(2)
}
main() {
    println("x")
}'
expect_error borrowed.ae "'b' is borrowed: a parameter of an owned type is the caller's to release" \
    "returning a borrowed owned parameter was not refused"
expect_error borrowed.ae "'b' is borrowed: a parameter of an owned type is the caller's, so it is not bound" \
    "rebinding a borrowed owned parameter was not refused"

case_file after_move 'main() {
    s = spawn(Sink())
    b = fill(1)
    s ! Chunk { data: move b }
    println(lend(b))
    wait_for_idle()
}'
expect_error after_move.ae "use of moved value 'b'" "a use after a move was not refused"

cat > "$tmp/bad_drop.ae" <<'AE'
release_nothing(p: ptr) {
    println("not freed")
}

type Buf = owned ptr drop release_nothing

main() {
    println("x")
}
AE
expect_error bad_drop.ae "owned type 'Buf' is released by 'release_nothing', which does not free a pointer it is given" \
    "a drop function that frees nothing was not refused"

# What stays legal, and runs: a lend, a local returned, moves into messages.
case_file ok 'main() {
    s = spawn(Sink())
    b = fill(3)
    println(lend(b))
    s ! Chunk { data: move b }
    s ! Chunk { data: fill(4) }
    wait_for_idle()
}'
got="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run ok.ae 2>&1 | tr -d '\r' | tr '\n' ' ')"
if [ "$got" != "3 3 4 " ]; then
    echo "  [FAIL] owned_ptr: a legal program was refused or misran (got '$got')"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "  [PASS] owned_ptr: one owner at a time; lends, returns and moves pass"
fi
exit $fail
