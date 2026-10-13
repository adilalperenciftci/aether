#!/bin/sh
# `none` and `[]` given through an erased `fn` are refused (#2840 review).
#
# Both are built as a value of the slot they are given to: an optional, or a
# slice of its element type. Through a bare `fn` with no closure literal
# known, the closure's parameter types are not known at the call, and the
# closure-call coercion of #2840 guessed one: `apply_none(f: fn) -> int {
# return call(f, none) }` called with `|o: string?|` built an int optional
# ("unresolved type in codegen, defaulting to int") and the program crashed.
# Each is now an error at the argument naming the fix; a local of the
# parameter's type passed instead runs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] erased_call_args: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# refused <name> <line:col> <text>: `ae check` refuses <name>.ae with E0200
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
        *"error[E0200]"*"$text"*"$name.ae:$at"*) ;;
        *) echo "  [FAIL] $name: not E0200 \"$text\" at $at:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

cat > "$TMP/none_call.ae" <<'AE'
apply_none(f: fn) -> int {
    return call(f, none)
}

main() {
    g = |o: string?| {
        return 1
    }
    println("${apply_none(g)}")
}
AE
refused none_call 2:20 "\`none\` given to 'f', a bare \`fn\`: its parameter types are not known here"

cat > "$TMP/none_direct.ae" <<'AE'
apply_none(f: fn) -> int {
    return f(none)
}

main() {
    g = |o: string?| {
        return 1
    }
    println("${apply_none(g)}")
}
AE
refused none_direct 2:14 "\`none\` given to 'f', a bare \`fn\`"

cat > "$TMP/empty_call.ae" <<'AE'
apply_empty(f: fn) -> int {
    return call(f, [])
}

main() {
    k = |xs: int[]| {
        return xs.len
    }
    println("${apply_empty(k)}")
}
AE
refused empty_call 2:20 "\`[]\` given to 'f', a bare \`fn\`"

cat > "$TMP/typed_local.ae" <<'AE'
apply(f: fn) -> int {
    let o: string? = none
    return call(f, o)
}

apply_list(f: fn) -> int {
    let e: int[] = []
    return call(f, e)
}

main() {
    g = |o: string?| {
        if o == none {
            return 1
        }
        return 2
    }
    k = |xs: int[]| {
        return xs.len + 5
    }
    println("typed ${apply(g)} ${apply_list(k)}")
}
AE
out=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run typed_local.ae 2>&1)
case "$out" in
    *"typed 1 5"*) ;;
    *) echo "  [FAIL] typed_local: not \"typed 1 5\":"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

if [ "$fails" -ne 0 ]; then
    echo "  [FAIL] erased_call_args: $fails case(s)"
    exit 1
fi
echo "  [PASS] erased_call_args: none and [] through a bare fn are refused"
