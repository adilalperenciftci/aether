#!/bin/sh
# One name per operation (#2976, E0305). A module may not export two names
# that answer to one short name: `add` beside `aether_set_add`, or `free`
# beside `m_free`. `m.add` reached one of them and `m.aether_m_add` the
# other, the same operation twice (std exported 336 such duplicates, std.mem
# alone 82), or, worse, a different one that reads as the same (std.set's
# extern returned 1 where its wrapper returns true). The error names both,
# at the later one in the list; a module with no exports list is held to it
# over its top-level declarations, and so is a module file checked on its
# own. A name whose short form would start with a digit keeps its own. In
# std, each duplicate is gone from the export lists: the long names are
# E0303, the wrappers answer.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
if [ ! -x "$AE" ]; then
    echo "  [SKIP] export_short_names: ae not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
export AETHER_HOME="$ROOT"
fail=0

# refused <name> <file> <text>...: `ae check <file>` fails, saying each text.
refused() {
    name="$1"
    file="$2"
    shift 2
    if (cd "$tmp" && "$AE" check "$file" >"$tmp/$name.log" 2>&1); then
        echo "  [FAIL] export_short_names: $name was accepted"
        fail=1
        return
    fi
    for want in "$@"; do
        if ! grep -qF -- "$want" "$tmp/$name.log"; then
            echo "  [FAIL] export_short_names: $name does not say: $want"
            sed 's/^/          /' "$tmp/$name.log" | head -8
            fail=1
        fi
    done
}

# A wrapper beside its extern, under both spellings of the prefix.
mkdir -p "$tmp/tally"
cat > "$tmp/tally/module.ae" <<'AE'
exports(aether_tally_add, tally_free, add, free)

extern aether_tally_add(n: int) -> int
extern tally_free(p: ptr)

add(n: int) -> bool {
    return aether_tally_add(n) == 1
}

free(p: ptr) {
    tally_free(p)
}
AE
cat > "$tmp/use_tally.ae" <<'AE'
import tally

main() {
    println("${tally.add(1)}")
}
AE
refused wrapper_beside_extern use_tally.ae \
    "error[E0305]: module 'tally' exports 'aether_tally_add' and 'add', two names that answer to one short name, 'tally.add'" \
    "error[E0305]: module 'tally' exports 'tally_free' and 'free', two names that answer to one short name, 'tally.free'" \
    "_raw"

# The module file checked on its own is held to the same rule.
refused module_on_its_own tally/module.ae "exports 'aether_tally_add' and 'add'"

# With no exports list, every top-level declaration is exported.
mkdir -p "$tmp/open"
cat > "$tmp/open/module.ae" <<'AE'
extern open_size(p: ptr) -> int

size(p: ptr) -> int {
    return open_size(p)
}
AE
cat > "$tmp/use_open.ae" <<'AE'
import open

main() {
    println("${open.size(null)}")
}
AE
refused implicit_exports use_open.ae "exports 'open_size' and 'size'"

# One name each is fine: a raw extern named so, a name whose short form
# would start with a digit (it keeps its own), and two names of their own.
mkdir -p "$tmp/hashy"
cat > "$tmp/hashy/module.ae" <<'AE'
exports(add, add_raw, hashy_256_hex, hex)

@extern("abs") add_raw(n: int) -> int

add(n: int) -> int {
    return add_raw(n) + 1
}

hashy_256_hex(n: int) -> int {
    return n * 2
}

hex(n: int) -> int {
    return n * 3
}
AE
cat > "$tmp/use_hashy.ae" <<'AE'
import hashy

main() {
    println("${hashy.add(-4)} ${hashy.add_raw(-4)} ${hashy.hashy_256_hex(5)} ${hashy.hex(5)}")
}
AE
out="$(cd "$tmp" && "$AE" run use_hashy.ae 2>&1 | tr -d '\r' | tail -1)"
if [ "$out" != "5 4 10 15" ]; then
    echo "  [FAIL] export_short_names: one name per operation was refused or printed: $out"
    fail=1
fi

# std: the wrappers answer, the duplicates are no longer exported.
cat > "$tmp/std_short.ae" <<'AE'
import std.set
import std.intarr
import std.string

main() {
    s = set.new()
    added = set.add(s, "a")
    println("${added} ${set.contains(s, "a")} ${set.size(s)}")
    set.free(s)
    a, _ = intarr.new(3)
    v = intarr.array(a)
    println("${v.len}")
    intarr.free(a)
    seq = string.seq_cons("a", string.seq_cons("b", string.seq_empty()))
    println(string.join(seq, "-"))
    string.seq_free(seq)
}
AE
out="$(cd "$tmp" && "$AE" run std_short.ae 2>&1 | tr -d '\r' | tail -3 | tr '\n' ' ')"
if [ "$out" != "true true 1 3 a-b " ]; then
    echo "  [FAIL] export_short_names: std's short names printed: $out"
    fail=1
fi
for long in "set.aether_set_add(null, \"a\")" "mem.aether_mem_get_byte(null, 0)" \
            "http.http_server_set_host(null, \"h\")" "intarr.intarr_array(null)" \
            "string.string_join(null, \"-\")"; do
    module="${long%%.*}"
    name="${long#*.}"
    name="${name%%(*}"
    cat > "$tmp/std_long.ae" <<AE
import std.$module

main() {
    _ = $long
}
AE
    refused "std_$name" std_long.ae "error[E0303]: '$name' is not exported from module"
done

if [ $fail -eq 0 ]; then
    echo "  [PASS] export_short_names: two exports of one short name are E0305, std exports one name per operation"
fi
exit $fail
