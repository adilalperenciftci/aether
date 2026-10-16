#!/bin/sh
# A function may not free a `string` or `*StringSeq` parameter (E0901,
# #2924).
#
# A parameter is borrowed for the call: the caller owns the string and frees
# it (docs/design/ownership-model.md, R3). `string.free(p)`, `release(p)`,
# `string.release(p)` or the runtime free bound under another name, on any
# path, would release a reference the function does not own. A parameter the
# body re-binds holds a string of its own from then on and may be freed, as
# may a local, a module `var`, and a field reached through a pointer.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] frees_borrowed: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# refused <name> <line:col> <param>: `ae check` refuses <name>.ae with E0901
# at that position, naming <param>.
refused() {
    name="$1"; at="$2"; param="$3"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $name: accepted"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    case "$out" in
        *"error[E0901]: '$param' is a parameter"*"$name.ae:$at"*) ;;
        *) echo "  [FAIL] $name: not E0901 for '$param' at $at:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

# accepted <name>: `ae check` accepts <name>.ae.
accepted() {
    name="$1"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -ne 0 ]; then
        echo "  [FAIL] $name: refused"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
}

cat > "$TMP/free_param.ae" <<'AE'
import std.string

drop(s: string) {
    string.free(s)
}

main() { drop("x") }
AE
refused free_param 4:11 s

cat > "$TMP/release_param.ae" <<'AE'
drop(s: string) {
    release(s)
}

main() { drop("x") }
AE
refused release_param 2:5 s

cat > "$TMP/alias_param.ae" <<'AE'
@extern("string_free") drop_raw(s: string)

drop(s: string) {
    drop_raw(s)
}

main() { drop("x") }
AE
refused alias_param 4:5 s

cat > "$TMP/some_path.ae" <<'AE'
import std.string

maybe(s: string, n: int) {
    if n > 0 {
        string.release(s)
    }
}

main() { maybe("x", 1) }
AE
refused some_path 5:15 s

cat > "$TMP/second_param.ae" <<'AE'
import std.string

set_owned(previous: string, value: string) -> string {
    fresh = string.copy(value)
    if previous != null { string.free(previous) }
    return fresh
}

main() { println(set_owned("a", "b")) }
AE
refused second_param 5:33 previous

cat > "$TMP/seq_param.ae" <<'AE'
import std.string

drop(s: *StringSeq) {
    string.seq_free(s)
}

main() { drop(string.split_to_seq("a,b", ",")) }
AE
refused seq_param 4:11 s

cat > "$TMP/seq_rebound.ae" <<'AE'
import std.string

walk(s: *StringSeq) -> int {
    s = string.seq_tail(s)
    n = string.seq_length(s)
    string.seq_free(s)
    return n
}

main() { println("${walk(string.split_to_seq("a,b", ","))}") }
AE
accepted seq_rebound

cat > "$TMP/rebound.ae" <<'AE'
import std.string

grow(s: string) -> int {
    s = string.concat(s, "!")
    n = string.length(s)
    string.free(s)
    return n
}

main() { println("${grow("x")}") }
AE
accepted rebound

cat > "$TMP/owned_places.ae" <<'AE'
import std.string

struct Item { name: string }

var last: string = ""

clear(it: *Item) {
    string.free(it.name)
    string.free(last)
    local = string.concat(it.name, "?")
    string.free(local)
}

main() {
    it = heap.new(Item)
    it.name = string.concat("a", "b")
    clear(it)
    heap.free(it)
}
AE
accepted owned_places

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] frees_borrowed: a parameter's free is refused on every path and alias; owned places may be freed"
