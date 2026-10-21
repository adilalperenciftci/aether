#!/bin/sh
# #3025: string.bytes(s) is a read-only view of a string's bytes, and the
# checker refuses the stores into it that it can see: an element store, `+=`
# and `++` (either position) through a local bound to the view, or to a
# sub-slice of a local bound to it. The issue's program is one of them. A
# local bound more than once (it may hold another slice by the time it is
# written), or the view given to a function, is checked at run time instead
# (tests/regression/test_issue3025_readonly_string_view.ae), and so is
# anything else; a slice of the program's own is written as before.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"
if [ ! -x "$AETHERC" ] && [ ! -x "$AETHERC.exe" ]; then
    echo "  [SKIP] readonly_string_view: $AETHERC not built"; exit 0
fi
export AETHER_HOME="$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
fail=0

want="is a read-only view of a string's bytes (string.bytes)"

# refused <name> <line:col>: the program on stdin is refused with the
# read-only view's message at that position.
refused() {
    name="$1"; at="$2"
    cat > "$tmp/$name.ae"
    if (cd "$tmp" && "$AETHERC" "$name.ae" "$name.c") >"$tmp/$name.log" 2>&1; then
        echo "  [FAIL] readonly_string_view: $name compiled (the store must be refused)"
        fail=1; return
    fi
    if ! grep -qF "$want" "$tmp/$name.log" || ! grep -qF "$name.ae:$at" "$tmp/$name.log"; then
        echo "  [FAIL] readonly_string_view: $name not refused with the read-only view's message at $at"
        sed 's/^/        /' "$tmp/$name.log" | head -8
        fail=1
    fi
}

# accepted <name>: the program on stdin compiles.
accepted() {
    name="$1"
    cat > "$tmp/$name.ae"
    if ! (cd "$tmp" && "$AETHERC" "$name.ae" "$name.c") >"$tmp/$name.log" 2>&1; then
        echo "  [FAIL] readonly_string_view: $name refused"
        sed 's/^/        /' "$tmp/$name.log" | head -8
        fail=1
    fi
}

# The issue's program.
refused issue_literal 5:10 <<'AE'
import std.string

main() {
    v = string.bytes("abc")
    v[0] = 66
    println("wrote ${v[0]}")
}
AE

refused heap_plus_assign 6:10 <<'AE'
import std.string

main() {
    s = string.concat("ab", "c")
    v = string.bytes(s)
    v[1] += 1
    println("${v[1]}")
}
AE

refused postfix_step 5:9 <<'AE'
import std.string

main() {
    v = string.bytes("abc")
    v[2]++
    println("${v[2]}")
}
AE

refused prefix_step 5:5 <<'AE'
import std.string

main() {
    v = string.bytes("abc")
    --v[0]
    println("${v[0]}")
}
AE

refused sub_slice 6:10 <<'AE'
import std.string

main() {
    v = string.bytes("abcd")
    w = v[1..3]
    w[0] = 1
    println("${w[0]}")
}
AE

refused in_function 4:24 <<'AE'
import std.string

scramble(s: string) {
    string.bytes(s)[0] = 1
}

main() { scramble("abc") }
AE

# Reads, a local bound again, and a slice of the program's own compile.
accepted reads <<'AE'
import std.string

main() {
    v = string.bytes("abc")
    total = 0
    i = 0
    while i < v.len {
        total = total + v[i]
        i = i + 1
    }
    w = v[1..]
    println("${total} ${w.len} ${w[0]}")
}
AE

accepted bound_again <<'AE'
import std.string

main() {
    v = string.bytes("abc")
    v = make([]byte, 3)
    v[0] = 66
    println("${v[0]}")
    free(v)
}
AE

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "  [PASS] readonly_string_view: a store the checker can see through string.bytes is refused; reads and other slices compile"
