#!/bin/sh
# A send or an ask to a null actor reference panics by name (#3172). It read
# the null actor's fields and the process died of an access violation, past
# the barrier that catches an actor's panic. Now a handler's send to null
# ends that actor alone, and main's own send or ask to null is a panic that
# names the operation and the place.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -x "$AE" ] || AE="$ROOT/build/ae.exe"
[ -x "$AE" ] || { echo "  [SKIP] null_actor_send: ae not built"; exit 0; }
. "$ROOT/tests/lib/sweep_timeout.sh"
sweep_timeout_bound BOUND "$ROOT" 60

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail() { echo "  [FAIL] null_actor_send: $1"; sed 's/^/    | /' "$tmp/out.txt" | head -8; exit 1; }

run() {  # file: build it, run it bounded, leave its output in out.txt and its status in rc
    AETHER_HOME="$ROOT" "$AE" build "$1" -o "$tmp/prog" >"$tmp/out.txt" 2>&1 || fail "$1 did not build"
    $BOUND "$tmp/prog" >"$tmp/out.txt" 2>&1
    rc=$?
}

# A stage whose successor is not connected yet: its send panics, the actor
# dies, and the program goes on.
cat > "$tmp/handler.ae" <<'AE'
message Number { n: int }

actor Stage {
    state next: actor_ref = null
    receive {
        Number(n) -> {
            next ! Number { n: n + 1 }
        }
    }
}

main() {
    s = spawn(Stage())
    s ! Number { n: 1 }
    wait_for_idle()
    println("end")
}
AE
run "$tmp/handler.ae"
[ "$rc" -eq 0 ] || fail "a handler's send to null took the program down (rc $rc)"
grep -q '^end' "$tmp/out.txt" || fail "the program did not go on after the actor's panic"

# The panic is an ordinary one: a try in the handler catches it, by name.
cat > "$tmp/caught.ae" <<'AE'
message Number { n: int }

actor Stage {
    state next: actor_ref = null
    receive {
        Number(n) -> {
            try {
                next ! Number { n: n + 1 }
            } catch e {
                println("caught: ${e}")
            }
        }
    }
}

main() {
    s = spawn(Stage())
    s ! Number { n: 1 }
    wait_for_idle()
    println("end")
}
AE
run "$tmp/caught.ae"
[ "$rc" -eq 0 ] || fail "a caught send to null took the program down (rc $rc)"
grep -q 'caught: null_actor_send: send to a null actor reference at .*caught.ae:8' "$tmp/out.txt" || fail "the caught panic does not name the send and its place"

# main's own send to null.
cat > "$tmp/main_send.ae" <<'AE'
message Number { n: int }

actor Stage {
    receive {
        Number(n) -> {
            println("${n}")
        }
    }
}

main() {
    let s: actor_ref = null
    s ! Number { n: 1 }
    println("unreachable")
}
AE
run "$tmp/main_send.ae"
[ "$rc" -ne 0 ] || fail "main's send to null did not panic"
grep -q 'null_actor_send: send to a null actor reference at .*main_send.ae:13' "$tmp/out.txt" || fail "main's send panic does not name the send and its place"
grep -q 'unreachable' "$tmp/out.txt" && fail "main went on after its send to null"

# main's ask of null.
cat > "$tmp/main_ask.ae" <<'AE'
message Get {}

actor Box {
    receive {
        Get -> {
            reply 7
        }
    }
}

main() {
    let b: actor_ref = null
    v = b ? Get {}
    println("${v}")
}
AE
run "$tmp/main_ask.ae"
[ "$rc" -ne 0 ] || fail "main's ask of null did not panic"
grep -q 'null_actor_ask: ask to a null actor reference at' "$tmp/out.txt" || fail "main's ask panic does not name the ask"

echo "  [PASS] null_actor_send"
