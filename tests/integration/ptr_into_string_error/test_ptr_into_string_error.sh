#!/bin/sh
# A bare `ptr` given to a `string` local (`s = map_get_raw(m, k)`, or a tuple
# slot, `s, err = map.get(m, k)`) is read as text whatever it points at: a
# list, a struct, bytes with no end. W1005 says so and names the typed
# accessor that says the value is a string and checks it is one
# (`map.get_string`, `list.get_string`, `string.from_ptr`). A warning now, an
# error in a later release.
#
# It must stay silent on what is not that: `null`, a `string.*` producer whose
# result is typed `ptr` (a counted string), the accessors themselves, a local
# whose first binding is the `ptr`, and a typed pointer.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] ptr_into_string_warn: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# warns <name> <line:col> <hint>: `ae check` accepts <name>.ae with exactly
# one W1005, at that position, naming <hint>.
warns() {
    name="$1"; at="$2"; hint="$3"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -ne 0 ]; then
        echo "  [FAIL] $name: refused"; echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    n=$(printf '%s\n' "$out" | grep -c "warning\[W1005\]")
    case "$out" in
        *"warning[W1005]"*"$name.ae:$at"*"$hint"*)
            if [ "$n" != "1" ]; then
                echo "  [FAIL] $name: $n W1005 warnings, want 1"
                fails=$((fails + 1))
            fi ;;
        *) echo "  [FAIL] $name: no W1005 at $at naming $hint:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

silent() {
    name="$1"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -ne 0 ] || printf '%s' "$out" | grep -q "W1005"; then
        echo "  [FAIL] $name: refused or warned W1005"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
}

cat > "$TMP/plain_map.ae" <<'AE'
import std.map

main() {
    m = map.new()
    map.put(m, "k", "v")
    s = "x"
    s = map_get_raw(m, "k")
    println(s)
    map.free(m)
}
AE
warns plain_map 7:5 "map.get_string(m, key)"

cat > "$TMP/tuple_map.ae" <<'AE'
import std.map

main() {
    m = map.new()
    map.put(m, "k", "v")
    name = ""
    name, err = map.get(m, "k")
    println("${name}${err}")
    map.free(m)
}
AE
warns tuple_map 7:5 "map.get_string(m, key)"

cat > "$TMP/plain_list.ae" <<'AE'
import std.list

main() {
    l = list.new()
    list.add(l, "a")
    s = ""
    s = list_get_raw(l, 0)
    println(s)
    list.free(l)
}
AE
warns plain_list 7:5 "list.get_string(l, index)"

cat > "$TMP/tuple_list.ae" <<'AE'
import std.list

main() {
    l = list.new()
    list.add(l, "a")
    s = ""
    s, err = list.get(l, 0)
    println("${s}${err}")
    list.free(l)
}
AE
warns tuple_list 7:5 "list.get_string(l, index)"

cat > "$TMP/plain_ptr.ae" <<'AE'
show(p: ptr) {
    s = ""
    s = p
    println(s)
}

main() { show(null) }
AE
warns plain_ptr 3:5 "string.from_ptr(p)"

cat > "$TMP/quiet.ae" <<'AE'
import std.map
import std.list
import std.string

struct Node { v: int }

main() {
    m = map.new()
    map.put(m, "k", "v")
    l = list.new()
    list.add(l, "a")
    s = "x"
    s = null
    s = string.from_int(7)
    s, err = map.get_string(m, "k")
    t = ""
    t, err2 = list.get_string(l, 0)
    p = map_get_raw(m, "k")
    p = list_get_raw(l, 0)
    u = ""
    u, err3 = string.from_ptr(p)
    n = heap.new(Node)
    q = n
    q = null as *Node
    println("${s} ${t} ${u} ${err}${err2}${err3} ${q == null}")
    heap.free(n)
    map.free(m)
    list.free(l)
}
AE
silent quiet

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] ptr_into_string_warn: a ptr given to a string local warns W1005 naming the typed accessor; null, string producers and the accessors stay silent"
