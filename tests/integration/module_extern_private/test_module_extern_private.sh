#!/bin/sh
# A bare `extern` belongs to the file that declares it. Every file's externs
# shared one global symbol, so the first declaration of a name registered
# was the one every file's calls were checked against: with arr's
# `extern memcpy(dst: ptr, src: int[], n: long)` loaded first, raw's own
# `memcpy(dst, src, 12)` with a ptr src was E0200 "expected int[], got a bare
# ptr", and whether a module built depended on what else the program
# imported, and in which order (ae3d: ae3d.vkspirv's memcpy broke 119 calls
# in other modules). A file that declares the extern is now checked against
# its own declaration: the program's against the program's, a module's
# against the module's. A call that is wrong for its own declaration is
# still an error. Code generation reads the same declaration: owned's
# `strdup` is `@heap` and lent's is not, so owned's call alone is adopted,
# with lent imported first.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] module_extern_private: ae not built"; exit 0; }

fail=0
for prog in both reversed own; do
    out="$(cd "$SCRIPT_DIR" && "$AE" run "$prog.ae" --lib lib 2>&1)"
    if [ "$out" != "0" ]; then
        echo "  [FAIL] module_extern_private: $prog.ae should build and copy the bytes intact"
        printf '%s\n' "$out" | head -8 | sed 's/^/        |/'
        fail=1
    fi
done

out="$(cd "$SCRIPT_DIR" && "$AE" run bad.ae --lib lib 2>&1)"
case "$out" in
    *memcpy*lib/bad/module.ae*) ;;
    *)
        echo "  [FAIL] module_extern_private: bad.ae's short memcpy call should be an error in lib/bad"
        printf '%s\n' "$out" | head -8 | sed 's/^/        |/'
        fail=1 ;;
esac

AETHERC="$ROOT/build/aetherc"
[ -n "${EXE_EXT:-}" ] && AETHERC="$AETHERC$EXE_EXT"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
if (cd "$SCRIPT_DIR" && "$AETHERC" --lib lib heap.ae "$tmp/heap.c" >"$tmp/heap.log" 2>&1); then
    adopted=$(grep -c 'aether_string_adopt(strdup(' "$tmp/heap.c")
    if [ "$adopted" != "1" ]; then
        echo "  [FAIL] module_extern_private: owned's @heap strdup call should be adopted, lent's not ($adopted adopted)"
        grep -n 'strdup(' "$tmp/heap.c" | sed 's/^/        |/'
        fail=1
    fi
else
    echo "  [FAIL] module_extern_private: heap.ae did not compile"
    sed 's/^/        |/' "$tmp/heap.log" | head -8
    fail=1
fi

[ $fail -eq 0 ] && echo "  [PASS] module_extern_private: each file's extern calls are checked against its own declaration, whatever else the program loads"
exit $fail
