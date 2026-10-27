#!/bin/sh
# `append(xs, v)` grows a buffer the program owns, releasing the old one as
# `free` does, so what `free` refuses `append` refuses (E0200): a sub-slice,
# a string's bytes, an array, each as a local bound once to it. A first
# argument that is no slice, an element of another type, and a slice of
# arrays are refused too. The owners, a program's own `append`, and a
# module's `append` (std.strbuilder) compile. What the checker cannot see is
# the run-time check's (tests/regression/test_slice_append.ae).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] slice_append: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# refused <name> <text> <line:col>: `ae check` refuses the program on stdin
# with an E0200 whose message holds <text>, at that position.
refused() {
    cat > "$TMP/$1.ae"
    out=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" check "$1.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $1: accepted"
        fails=$((fails + 1))
        return
    fi
    case "$out" in
        *"error[E0200]"*"$2"*"$1.ae:$3"*) ;;
        *) echo "  [FAIL] $1: not E0200 \"$2\" at $3"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

# accepted <name>: `ae check` takes the program on stdin.
accepted() {
    cat > "$TMP/$1.ae"
    out=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" check "$1.ae" 2>&1)
    if [ $? -ne 0 ]; then
        echo "  [FAIL] $1: refused"
        echo "$out" | sed 's/^/        /' | head -8
        fails=$((fails + 1))
    fi
}

refused sub_local "cannot append to 's': it is a view of elements another slice or an array holds" 4:9 <<'AE'
main() {
    b = make([]int, 8)
    s = b[2..4]
    t = append(s, 1)
    println("${t.len}")
    free(b)
}
AE

refused bytes_local "cannot append to 'v': it is a read-only view of a string's bytes" 5:9 <<'AE'
import std.string

main() {
    v = string.bytes("abc")
    w = append(v, 1)
    println("${w.len}")
}
AE

refused array_value "cannot append to 'arr': an array \`int[2]\` lives in its function or its struct" 3:9 <<'AE'
main() {
    arr = [1, 2]
    u = append(arr, 3)
    println("${u.len}")
}
AE

refused not_a_slice "append(xs, v) takes a slice \`T[]\` as its first argument, got int" 3:9 <<'AE'
main() {
    n = 3
    m = append(n, 1)
    println("${m}")
}
AE

refused wrong_element "append(xs, v): v is string, but the elements of xs are int" 3:19 <<'AE'
main() {
    b = make([]int, 0)
    b = append(b, "x")
    free(b)
}
AE

refused array_elements "append(xs, v) does not take a slice of arrays" 3:12 <<'AE'
main() {
    rows = make([]int[2], 0)
    rows = append(rows, [1, 2])
    free(rows)
}
AE

accepted owners <<'AE'
grow(xs: int[], n: int) -> int[] {
    for i in 0..n {
        xs = append(xs, i)
    }
    return xs
}

main() {
    int[] a = []
    a = append(a, 1)
    a = grow(a, 3)
    b = make([]string, 2)
    b = append(b, "x")
    free(a)
    free(b)
}
AE

accepted own_append <<'AE'
append(xs: int[], x: int) -> int {
    return xs.len + x
}

main() {
    a = [1, 2]
    println("${append(a, 5)}")
}
AE

accepted strbuilder_append <<'AE'
import std.strbuilder

main() {
    b = strbuilder.new(16)
    strbuilder.append(b, "hi")
    strbuilder.free(b)
}
AE

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] slice_append: views and mistyped appends refused; owners and other appends compile"
