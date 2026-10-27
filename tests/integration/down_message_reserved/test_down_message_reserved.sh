#!/bin/sh
# `Down` is the runtime's death notice (#2974): the compiler declares
# `message Down { ref: actor_ref, reason: string }` and the runtime writes its
# payload, so a program's own `message Down` is refused, naming the shape,
# before the C compiler could see two structs of one name.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE_TMP="$(mktemp -d)"
trap 'rm -rf "$AE_TMP"' EXIT

cat > "$AE_TMP/bad.ae" << 'AE'
message Down { who: int }
actor Watcher {
    state n = 0
    receive { Down(who) -> { n = n + who } }
}

main() {
    w = spawn(Watcher())
    w ! Down { who: 1 }
    wait_for_idle()
}
AE
if out=$(AETHER_HOME="$ROOT" "$ROOT/build/ae" build "$AE_TMP/bad.ae" -o "$AE_TMP/bad" 2>&1); then
    echo "  [FAIL] down_message_reserved: a program's own message Down compiled"
    exit 1
fi
if ! echo "$out" | grep -q "'Down' is the runtime's death notice"; then
    echo "  [FAIL] down_message_reserved: the error does not say Down is the runtime's"
    echo "$out" | sed 's/^/    /' | head -10
    exit 1
fi
echo "  [PASS] down_message_reserved"
