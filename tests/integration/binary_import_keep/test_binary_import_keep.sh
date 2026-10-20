#!/bin/sh
# A binary import is checked as a source import is (#3013). A library's
# catalog gives each export its source signature, and `ae` declares the
# export for the importer from it. That signature left `@keep` out, so a
# `@keep ptr` parameter was a borrowing extern parameter to the importer:
# a string went to it implicitly and a borrowed `ptr` was passed on to it,
# both E0902 in a source import. The signature now spells `@keep` and
# `@into` (#2990), the extern takes them as they are, and `ae check`
# resolves a binary import as `ae build` does.
#
# Each importer is checked twice, against the module's source and against
# the library built from it, and must get the same verdict; the accepted
# one is built and run against the library.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] binary_import_keep: ae not built"; exit 0; }

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT) SO_EXT=".dll";   EXE=".exe" ;;
    Darwin)                          SO_EXT=".dylib"; EXE="" ;;
    *)                               SO_EXT=".so";    EXE="" ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" || true' EXIT
cd "$WORK"
fails=0

cat > keeper.ae <<'AE'
var kept: ptr = null

hold(p: @keep ptr) {
    kept = p
}

wrap(p: @into ptr) -> ptr {
    return p
}

count() -> int {
    if kept == null { return 0 }
    return 1
}

animate(el: @keep ptr, ticks: int, tick: fn(@keep ptr, float)) {
    i = 0
    while i < ticks {
        tick(el, 0.5)
        i = i + 1
    }
}
AE

# A function-typed parameter carries its modes across the catalog too
# (`tick: fn(@keep ptr, float)`, which it spelled `tick: fn`): an importer
# passing a keeping function is accepted, as from the source. Checked, not
# built: a named function given to a binary import's closure parameter
# does not build whatever its modes (its adapter is never emitted).
cat > fn_keep.ae <<'AE'
import keeper
import std.list

var registry: ptr = null

fill(el: @keep ptr, t: float) {
    list.add(registry, el)
}

main() {
    registry = list.new()
    shape = list.new()
    keeper.animate(shape, 3, fill)
    println("${list.size(registry)}")
}
AE

# So is a closure that declares `@keep`, and an untyped one, whose `e`
# takes `@keep ptr` from the type; both keep what they are given.
cat > fn_closure.ae <<'AE'
import keeper
import std.list

var registry: ptr = null

main() {
    registry = list.new()
    shape = list.new()
    keeper.animate(shape, 2) callback | e: @keep ptr, t: float | { list.add(registry, e) }
    keeper.animate(shape, 1) callback | e, t | { list.add(registry, e) }
    println("${list.size(registry)}")
}
AE

cat > string_to_keep.ae <<'AE'
import keeper
import std.string

main() {
    s = string.concat("a", string.from_int(1))
    keeper.hold(s)
}
AE

cat > borrowed_to_keep.ae <<'AE'
import keeper

relay(p: ptr) {
    keeper.hold(p)
}

main() { relay(null) }
AE

cat > into_escapes.ae <<'AE'
import keeper

var last: ptr = null

relay(p: ptr) {
    last = keeper.wrap(p)
}

main() { relay(null) }
AE

cat > string_to_into.ae <<'AE'
import keeper
import std.string

main() {
    s = string.concat("a", string.from_int(1))
    w = keeper.wrap(s)
    println("${w == null}")
}
AE

cat > accepted.ae <<'AE'
import keeper
import std.string

relay(p: @keep ptr) {
    keeper.hold(p)
}

look(p: ptr) -> int {
    w = keeper.wrap(p)
    if w == p { return 1 }
    return 0
}

main() {
    s = string.concat("k", string.from_int(7))
    relay(string.keep(s))
    x = 0
    println("${keeper.count()} ${look((&x) as ptr)}")
}
AE

# verdict <file>: "ok", or each E0902 message and position, one a line.
verdict() {
    out=$(AETHER_HOME="$ROOT" "$AE" check "$1" 2>&1)
    if [ $? -eq 0 ]; then echo ok; return; fi
    printf '%s\n' "$out" | grep -E "^error|-->" | sed 's/^ *//'
}

for app in string_to_keep borrowed_to_keep into_escapes string_to_into accepted fn_keep fn_closure; do
    verdict "$app.ae" > "$app.source"
done

AETHER_HOME="$ROOT" "$AE" build --emit=lib keeper.ae -o "libkeeper$SO_EXT" >lib.log 2>&1 || {
    echo "  [FAIL] binary_import_keep: ae build --emit=lib keeper.ae"; sed 's/^/    /' lib.log; exit 1; }
mv keeper.ae keeper.src   # every importer resolves `keeper` to the library from here on

INFO="$(AETHER_HOME="$ROOT" "$AE" lib-info "./libkeeper$SO_EXT" 2>&1)"
for want in "as: hold(p: @keep ptr) -> void" "as: wrap(p: @into ptr) -> ptr" \
            "as: animate(el: @keep ptr, ticks: int, tick: fn(@keep ptr, float)) -> void"; do
    case "$INFO" in
        *"$want"*) ;;
        *) echo "  [FAIL] binary_import_keep: the catalog lacks \"$want\""
           echo "$INFO" | sed 's/^/    /'; fails=$((fails + 1)) ;;
    esac
done

for app in string_to_keep borrowed_to_keep into_escapes string_to_into accepted fn_keep fn_closure; do
    verdict "$app.ae" > "$app.binary"
    if [ "$(cat "$app.source")" != "$(cat "$app.binary")" ]; then
        echo "  [FAIL] binary_import_keep: $app is checked differently as a binary import"
        echo "    source import:"; sed 's/^/      /' "$app.source"
        echo "    binary import:"; sed 's/^/      /' "$app.binary"
        fails=$((fails + 1))
    fi
done

# What each verdict must be, as a source import gives it.
expect() {
    grep -qF "$2" "$1.binary" || {
        echo "  [FAIL] binary_import_keep: $1 is not \"$2\""; sed 's/^/    /' "$1.binary"
        fails=$((fails + 1)); }
}
expect string_to_keep "a \`string\` is given to a \`@keep ptr\` parameter"
expect borrowed_to_keep "'p' is a borrowed \`ptr\` parameter, passed to a parameter that keeps it"
expect into_escapes "'p' is a borrowed \`ptr\` parameter, stored in a module-level \`var\`"
expect string_to_into "a \`string\` is given to an \`@into ptr\` parameter"
expect accepted "ok"
expect fn_keep "ok"
expect fn_closure "ok"

# run_app <name> <want>: built against the library, it prints <want>.
run_app() {
    AETHER_HOME="$ROOT" "$AE" build "$1.ae" -o "$1" >"$1.log" 2>&1 || {
        echo "  [FAIL] binary_import_keep: ae build $1.ae"; sed 's/^/    /' "$1.log"
        fails=$((fails + 1)); return; }
    OUT="$("./$1$EXE" 2>&1)"
    [ "$OUT" = "$2" ] || {
        echo "  [FAIL] binary_import_keep: $1 printed \"$OUT\", want \"$2\""; fails=$((fails + 1)); }
}
run_app accepted "1 1"
run_app fn_closure "3"

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] binary_import_keep: @keep and @into cross the catalog, in a function type too; a binary import is checked as the source import is"
