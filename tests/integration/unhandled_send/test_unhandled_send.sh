#!/bin/sh
# A send or an ask of a message the target actor has no receive arm for is
# refused at compile time, where the target's type names its actor (#385).
#
# A send only checked that the target was an actor reference and that the
# message was declared. A message the actor had no arm for passed `ae check`
# and was dropped at run time without a word. The target's type says which
# actor it is for a `spawn(A())` result and for a reference typed
# `actor_ref[A]`; there the actor's arms are known, and a message none of
# them names (and no `_` arm takes) is an error naming the actor and the
# message. A bare `actor_ref` is the dynamic escape and is not checked. The
# actor may come from an imported module.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] unhandled_send: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0

expect_error() {  # file, fixed string, label
    out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" check "$1" 2>&1)"
    if ! printf '%s' "$out" | grep -qF "$2"; then
        echo "  [FAIL] unhandled_send: $3"
        printf '%s\n' "$out" | grep -E "^error|-->" | head -4 | sed 's/^/        /'
        fail=1
    fi
}

expect_run() {  # file, expected last line, label
    got="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run "$1" 2>&1 | tr -d '\r' | tail -1)"
    if [ "$got" != "$2" ]; then
        echo "  [FAIL] unhandled_send: $3 (got '$got')"
        fail=1
    fi
}

# A spawn result, a parameter typed actor_ref[Writer], and an ask.
cat > "$tmp/refused.ae" <<'AE'
message Open { path: string }
message Close {}
message Size {}

actor Writer {
    receive {
        Open(path) -> { println(path) }
    }
}

close_it(w: actor_ref[Writer]) {
    w ! Close {}
}

main() {
    w = spawn(Writer())
    w ! Open { path: "a" }
    w ! Close {}
    close_it(w)
    n = w ? Size {}
    println(n)
    wait_for_idle()
}
AE
expect_error refused.ae "refused.ae:18:9" "a send through a spawn result was not refused"
expect_error refused.ae "actor 'Writer' has no receive arm for 'Close', so this message would be dropped" \
    "the refusal does not name the actor and the message"
expect_error refused.ae "refused.ae:12:9" "a send through an actor_ref[Writer] parameter was not refused"
expect_error refused.ae "refused.ae:20:13" "an ask was not refused"
expect_error refused.ae "add an arm for \`Close\` (or a \`_\` arm) to 'Writer'" "the help line is missing"

# What stays legal: a handled message, a bare actor_ref, a `_` arm, and an
# actor and its messages from an imported module.
mkdir -p "$tmp/lib/files"
cat > "$tmp/lib/files/module.ae" <<'AE'
exports(Store, Put, Get)

message Put { n: int }
message Get {}

actor Store {
    state total = 0
    receive {
        Put(n) -> { total = total + n }
        Get() -> { reply total }
    }
}
AE
cat > "$tmp/ok.ae" <<'AE'
import files

message Open { path: string }
message Close {}

var closed = 0

actor Writer {
    receive {
        Open(path) -> { println(path) }
    }
}

actor Any {
    receive {
        Open(path) -> { println(path) }
        _ -> { closed = closed + 1 }
    }
}

// Not checked: the reference names no actor.
close_any(w: actor_ref) {
    w ! Close {}
}

main() {
    w = spawn(Writer())
    w ! Open { path: "opened" }
    close_any(w)
    a = spawn(Any())
    a ! Close {}
    s = spawn(Store())
    s ! Put { n: 4 }
    t = s ? Get {}
    wait_for_idle()
    println("${t} ${closed}")
}
AE
expect_run ok.ae "4 1" "a legal program was refused or misran"

# A message the imported actor has no arm for is refused too.
cat > "$tmp/imported.ae" <<'AE'
import files

message Drop {}

main() {
    s = spawn(Store())
    s ! Drop {}
    wait_for_idle()
}
AE
expect_error imported.ae "actor 'Store' has no receive arm for 'Drop'" \
    "a send to an imported actor was not checked"

# A second `_` arm can never run (#3289).
cat > "$tmp/two.ae" <<'AE'
message A {}

actor X {
    receive {
        _ -> { println("one") }
        A() -> { println("a") }
        _ -> { println("two") }
    }
}

main() {
    x = spawn(X())
    x ! A {}
    wait_for_idle()
}
AE
expect_error two.ae "this \`_\` arm can never run: the \`_\` arm at line 5" "a second _ arm was not refused"

if [ "$fail" = 0 ]; then
    echo "  [PASS] unhandled_send: a send or ask no arm takes is refused; handled, bare, _ and imported sends pass"
fi
exit $fail
