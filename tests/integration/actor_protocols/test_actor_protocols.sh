#!/bin/sh
# Actor protocols: the messages an actor reference may be sent, and in which
# order, checked at compile time (#385).
#
#     protocol FileWriter {
#         start -> Open -> writing
#         writing -> Write -> writing
#         writing -> Close -> done
#     }
#     actor Writer implements FileWriter { ... }
#
# A reference to Writer is followed through the function that holds it: a
# send or ask the protocol does not allow in a state the reference may be in
# there is an error, after a branch, around a loop and through a parameter
# typed actor_ref[FileWriter] alike. Passing, copying, capturing or
# deferring the reference lets its state change out of sight, so later sends
# through it are not followed in order. An actor that implements a protocol
# has an arm for each of its messages, and a protocol names declared
# messages and one next state per state and message.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] actor_protocols: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0

expect_error() {  # file, fixed string, label
    out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" check "$1" 2>&1)"
    if ! printf '%s' "$out" | grep -qF -- "$2"; then
        echo "  [FAIL] actor_protocols: $3"
        printf '%s\n' "$out" | grep -E "^error|-->" | head -6 | sed 's/^/        /'
        fail=1
    fi
}

expect_errors() {  # file, count, label
    n="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" check "$1" 2>&1 | grep -c '^error\[E0600\]')"
    if [ "$n" != "$2" ]; then
        echo "  [FAIL] actor_protocols: $3 ($n errors, expected $2)"
        fail=1
    fi
}

expect_run() {  # file, expected output (lines joined by |), label
    got="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run "$1" 2>&1 | tr -d '\r' | tr '\n' '|')"
    if [ "$got" != "$2" ]; then
        echo "  [FAIL] actor_protocols: $3"
        echo "        got:      $got"
        echo "        expected: $2"
        fail=1
    fi
}

cat > "$tmp/proto.ae" <<'AE'
message Open { path: string }
message Write { data: string }
message Size {}
message Close {}
message Fail { reason: string }

protocol FileWriter {
    start -> Open -> writing
    writing -> Write -> writing
    writing -> Size -> writing
    writing -> Close -> done
    writing -> Fail -> done
}

actor Writer implements FileWriter {
    state lines = 0
    receive {
        Open(path) -> { println("open ${path}") }
        Write(data) -> { lines = lines + 1 }
        Size() -> { reply lines }
        Close() -> { println("closed after ${lines}") }
        Fail(reason) -> { println("failed: ${reason}") }
    }
}
AE

# A legal program: a loop, an ask, a parameter typed with the protocol, a
# branch whose arms both end the protocol, and a constant condition.
cat "$tmp/proto.ae" > "$tmp/ok.ae"
cat >> "$tmp/ok.ae" <<'AE'

const VERBOSE = false

write_n(w: actor_ref[FileWriter], n: int) {
    i = 0
    while i < n {
        w ! Write { data: "x" }
        i = i + 1
    }
}

main() {
    w = spawn(Writer())
    w ! Open { path: "out.txt" }
    write_n(w, 3)
    w ! Write { data: "more" }
    n = w ? Size {}
    if VERBOSE {
        w ! Close {}
    }
    if n == 4 {
        w ! Close {}
    } else {
        w ! Fail { reason: "short" }
    }
    wait_for_idle()

    v = spawn(Writer())
    v ! Open { path: "two.txt" }
    for (k = 0; k < 2; k = k + 1) {
        v ! Write { data: "y" }
    }
    v ! Fail { reason: "done early" }
    wait_for_idle()
}
AE
expect_run ok.ae "open out.txt|closed after 4|open two.txt|failed: done early|" \
    "a program that follows its protocol was refused or misran"

# Sends the protocol does not allow.
cat "$tmp/proto.ae" > "$tmp/bad.ae"
cat >> "$tmp/bad.ae" <<'AE'

late(w: actor_ref[FileWriter]) {
    w ! Close {}
    w ! Write { data: "late" }
}

main() {
    w = spawn(Writer())
    w ! Write { data: "before open" }
    w ! Open { path: "a" }
    k = 0
    if k > 0 {
        w ! Close {}
    }
    w ! Write { data: "maybe closed" }
    while k < 3 {
        w ! Close {}
        k = k + 1
    }
    x = spawn(Writer())
    x ! Open { path: "b" }
    n = x ? Size {}
    x ! Close {}
    m = x ? Size {}
    println("${n} ${m}")
    late(w)
    wait_for_idle()
}
AE
expect_error bad.ae "protocol 'FileWriter' does not allow 'Write' here: 'w' is in state 'start'" \
    "a send before the protocol's first message was not refused"
expect_error bad.ae "bad.ae:33:9" "the refusal does not point at the send"
expect_error bad.ae "help: in 'start' it takes Open" "the help line does not say what the state takes"
expect_error bad.ae "protocol 'FileWriter' does not allow 'Write' here: 'w' may be in state 'done'" \
    "a send after a branch that may have closed was not refused"
expect_error bad.ae "protocol 'FileWriter' does not allow 'Close' here: 'w' may be in state 'done'" \
    "a second Close around a loop was not refused"
expect_error bad.ae "protocol 'FileWriter' does not allow 'Size' here: 'x' is in state 'done'" \
    "an ask after the end of the protocol was not refused"
expect_error bad.ae "bad.ae:28:9" "a send through a protocol-typed parameter after Close was not refused"
expect_errors bad.ae 5 "the sends the protocol allows were refused too"

# A message the protocol does not have.
cat "$tmp/proto.ae" > "$tmp/notin.ae"
cat >> "$tmp/notin.ae" <<'AE'

message Flush {}

direct(w: actor_ref[FileWriter]) {
    w ! Flush {}
}

main() {
    w = spawn(Writer())
    direct(w)
    wait_for_idle()
}
AE
expect_error notin.ae "protocol 'FileWriter' has no message 'Flush'" \
    "a message outside the protocol was sent through actor_ref[FileWriter]"

# The way out: a bare actor_ref, a copy, a closure and a defer each let the
# state change out of sight, and nothing after them is refused.
cat "$tmp/proto.ae" > "$tmp/escape.ae"
cat >> "$tmp/escape.ae" <<'AE'

finish(w: actor_ref) {
    w ! Close {}
}

main() {
    w = spawn(Writer())
    w ! Open { path: "a" }
    finish(w)
    w ! Write { data: "the state is not known here" }

    x = spawn(Writer())
    x ! Open { path: "b" }
    y = x
    y ! Close {}
    x ! Write { data: "nor here" }

    z = spawn(Writer())
    z ! Open { path: "c" }
    later = || { z ! Close {} }
    later()
    z ! Write { data: "nor here" }
    wait_for_idle()
}
AE
expect_errors escape.ae 0 "a reference whose state changed out of sight was still followed"

# The declarations.
cat > "$tmp/decl.ae" <<'AE'
message A {}
message B {}

protocol P {
    s0 -> A -> s1
    s0 -> A -> s2
    s1 -> Missing -> s0
}

protocol Q {
    x -> B -> y
}

actor X implements Q {
    receive {
        A() -> { println("a") }
        _ -> { println("other") }
    }
}

actor Y implements Nope {
    receive {
        A() -> { println("a") }
    }
}

main() {
    _x = spawn(X())
    wait_for_idle()
}
AE
expect_error decl.ae "protocol 'P' has a second transition for 'A' in state 's0'; the first is at line 5" \
    "two next states for one state and message were not refused"
expect_error decl.ae "protocol 'P' names 'Missing', which is not a declared message" \
    "a protocol naming an undeclared message was not refused"
expect_error decl.ae "actor 'X' implements protocol 'Q' but has no receive arm for 'B'" \
    "an actor missing a protocol arm (a _ arm does not count) was not refused"
expect_error decl.ae "actor 'Y' implements 'Nope', which is not a declared protocol" \
    "an unknown protocol was not refused"

# A protocol and the actor implementing it from an imported module.
mkdir -p "$tmp/lib/door"
cat > "$tmp/lib/door/module.ae" <<'AE'
exports(Door, DoorUse, Unlock, Enter, Leave)

message Unlock {}
message Enter {}
message Leave {}

protocol DoorUse {
    locked -> Unlock -> open
    open -> Enter -> inside
    inside -> Leave -> open
}

actor Door implements DoorUse {
    receive {
        Unlock() -> { println("unlocked") }
        Enter() -> { println("in") }
        Leave() -> { println("out") }
    }
}
AE
cat > "$tmp/door_ok.ae" <<'AE'
import door

main() {
    d = spawn(Door())
    d ! Unlock {}
    d ! Enter {}
    d ! Leave {}
    wait_for_idle()
}
AE
expect_run door_ok.ae "unlocked|in|out|" "an imported protocol's legal sequence was refused or misran"
cat > "$tmp/door_bad.ae" <<'AE'
import door

main() {
    d = spawn(Door())
    d ! Enter {}
    wait_for_idle()
}
AE
expect_error door_bad.ae "protocol 'DoorUse' does not allow 'Enter' here: 'd' is in state 'locked'" \
    "an imported protocol was not followed"

if [ "$fail" = 0 ]; then
    echo "  [PASS] actor_protocols: sends follow the protocol through branches, loops and parameters; declarations checked"
fi
exit $fail
