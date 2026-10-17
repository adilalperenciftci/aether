#!/bin/sh
# A glob import of std.string, std.list or std.map (each defines a `free`)
# hid the builtin `free` from every other module of the program: a module
# calling `free(p)` without declaring it, std.cryptography included, was
# "Undefined function 'free'". The check that keeps a program's imports out
# of a module's merged body (a module's bare name found through the
# program's import is one it never imported) asked whether the program
# imported the NAME, and the glob names `free`, though the symbol a module
# found was the builtin, which the glob does not bind. It now asks whether
# the import bound the symbol. The module's bare `free` is also not
# rewritten to the program's `string.free`, so it frees with C's free.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT" && AETHERC="$AETHERC$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] glob_import_builtin_free: ae not built"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
fail=0
for prog in glob_string glob_list glob_map; do
    out="$(cd "$SCRIPT_DIR" && AETHER_HOME="$ROOT" "$AE" run "$prog.ae" --lib lib 2>&1)"
    if [ "$out" != "ok" ]; then
        echo "  [FAIL] glob_import_builtin_free: $prog.ae should build and run"
        printf '%s\n' "$out" | head -8 | sed 's/^/        |/'
        fail=1
    fi
    if (cd "$SCRIPT_DIR" && AETHER_HOME="$ROOT" "$AETHERC" --lib lib "$prog.ae" "$tmp/$prog.c" >"$tmp/$prog.log" 2>&1); then
        body="$(sed -n '/ mymod_rel(.*) {$/,/^}/p' "$tmp/$prog.c")"
        case "$body" in
            *_free\(*)
                echo "  [FAIL] glob_import_builtin_free: $prog.ae: mymod's bare free became the program's import"
                printf '%s\n' "$body" | sed 's/^/        |/'
                fail=1 ;;
            *free\(*) ;;
            *)
                echo "  [FAIL] glob_import_builtin_free: $prog.ae: no mymod_rel body with a free in the C"
                fail=1 ;;
        esac
    fi
done
out="$(cd "$SCRIPT_DIR" && AETHER_HOME="$ROOT" "$AE" run glob_crypto.ae 2>&1)"
if [ "$out" != "64" ]; then
    echo "  [FAIL] glob_import_builtin_free: std.cryptography under a std.string glob should build"
    printf '%s\n' "$out" | head -8 | sed 's/^/        |/'
    fail=1
fi
[ $fail -eq 0 ] && echo "  [PASS] glob_import_builtin_free: a glob import binds its own names, never another module's builtin free"
exit $fail
