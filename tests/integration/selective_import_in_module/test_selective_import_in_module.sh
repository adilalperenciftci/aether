#!/bin/sh
# A module's imports are its own (asks/selective-import-extern-short-name-in-module.md).
#
#   1. A module's selective import binds an extern-backed short name
#      (`import std.http (server_create)` for `extern http_server_create`),
#      as its glob import has since #2637 and as a program file's does.
#   2. A program's imports do not reach into the modules it imports: a
#      module that calls a bare `server_create` without importing std.http
#      fails, whether the program imported it selectively or with a glob.
#      It used to build or not depending on which program imported the
#      module (aeo's runner and agent disagreed).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] selective_import_in_module: ae not built"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
pass=0
fail=0
ok() { echo "  [PASS] selective_import_in_module: $1"; pass=$((pass + 1)); }
bad() { echo "  [FAIL] selective_import_in_module: $1"; fail=$((fail + 1)); }

# <dir> <module source> <program source>
setup() {
    mkdir -p "$tmp/$1/lib/mm"
    printf '%s\n' "$2" > "$tmp/$1/lib/mm/module.ae"
    printf '%s\n' "$3" > "$tmp/$1/main.ae"
}
build() { (cd "$tmp/$1" && "$AE" build main.ae -o prog --lib lib > build.log 2>&1); }

PROG_PLAIN='import mm

main() {
    p = mm.mk()
    println("built")
}'

# 1. The gap: a module's selective import of an extern-backed name.
setup gap 'import std.http (server_create)

exports(mk)

mk() -> ptr {
    return server_create(0)
}' "$PROG_PLAIN"
if build gap; then ok "a module's selective import binds an extern-backed short name"
else bad "a module's selective import of server_create failed"; sed 's/^/        /' "$tmp/gap/build.log" | head -4; fi

# 1b. ...and an Aether function from another local module still works.
setup fn 'import helper (twice)

exports(mk)

mk() -> ptr {
    n = twice(2)
    return null
}' "$PROG_PLAIN"
mkdir -p "$tmp/fn/lib/helper"
printf 'exports(twice)\n\ntwice(n: int) -> int {\n    return n * 2\n}\n' > "$tmp/fn/lib/helper/module.ae"
if build fn; then ok "a module's selective import of another module's Aether function still works"
else bad "a module's selective import of twice failed"; sed 's/^/        /' "$tmp/fn/build.log" | head -4; fi

# 2. The leak, through a program's selective import and through its glob.
NOIMPORT='exports(mk)

mk() -> ptr {
    return server_create(0)
}'
for form in "import std.http (server_create)" "import std.http (*)"; do
    setup leak "$NOIMPORT" "$form
import mm

main() {
    p = mm.mk()
    println(\"built\")
}"
    if build leak; then
        bad "a module without the import built because the program wrote '$form'"
    elif grep -q "Undefined function 'server_create'" "$tmp/leak/build.log"; then
        ok "'$form' in the program does not reach into the module"
    else
        bad "the leak case failed for another reason:"; sed 's/^/        /' "$tmp/leak/build.log" | head -4
    fi
done

# 3. The module can still use the name once it imports it itself, with the
#    program importing it too (no clash between the two bindings).
setup both 'import std.http (server_create)

exports(mk)

mk() -> ptr {
    return server_create(0)
}' 'import std.http (server_create)
import mm

main() {
    p = mm.mk()
    q = server_create(0)
    println("built")
}'
if build both; then ok "program and module each importing server_create build together"
else bad "program and module both importing server_create failed"; sed 's/^/        /' "$tmp/both/build.log" | head -4; fi

echo ""
echo "selective import in module: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
