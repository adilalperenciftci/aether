#!/bin/sh
# #3018: every std function that returns a string is typed `string`, and a
# `ptr` has no rendering.
#
# string.from_int, from_long, from_float, from_char, from_int_radix,
# pad_start, pad_end, format, new, new_with_length and empty returned their
# counted string as a `ptr`: nothing released it, so each call leaked it, and
# it could not go in a `string` local (E0202). string.array_get returned the
# array's characters as a `ptr` too, which dangled once the array was freed.
# Interpolation and print rendered any `ptr` as a C string, a list handle
# included. Now each result is a `string` the place that takes it owns (no
# heap growth over rounds of calls), array_get's value is copied by the local
# that keeps it, and rendering a `ptr` is refused before C. The typed
# new_with_length lines rest on #3030 (a string goes to it as its
# characters). Each program runs on the
# default C path and the strict C11 one.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"
if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then echo "  [SKIP] std_strings_typed: $AE not built"; exit 0; fi
export AETHER_HOME="$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" || true' EXIT
CC_BIN="${CC:-cc}"
command -v "$CC_BIN" >/dev/null 2>&1 || CC_BIN=gcc
fail=0

# <name> <text the diagnostic must contain>; the program is on stdin.
refused() {
    name="$1"; want="$2"
    cat > "$tmp/$name.ae"
    if "$AETHERC" "$tmp/$name.ae" "$tmp/$name.c" >"$tmp/$name.log" 2>&1; then
        echo "  [FAIL] std_strings_typed: $name compiled (it must be refused before C)"
        fail=1; return
    fi
    if ! grep -qF "$want" "$tmp/$name.log"; then
        echo "  [FAIL] std_strings_typed: $name refused, but not with: $want"
        sed 's/^/        /' "$tmp/$name.log" | head -6
        fail=1
    fi
}

refused interp_handle "cannot interpolate a \`ptr\`" <<'AE'
import std.list
main() {
    l = list.new()
    println("list ${l}")
    list.free(l)
}
AE
refused print_ptr "cannot print a \`ptr\`" <<'AE'
main() {
    ptr p = null
    println(p)
}
AE

cat > "$tmp/typed.ae" <<'AE'
import std.string
import std.list
import std.mem

// A piece of a split, kept past the array's free.
piece(s: string, i: int) -> string {
    parts = string.split(s, ",")
    v = string.array_get(parts, i)
    string.array_free(parts)
    return v
}

// Every retyped function, its result held in a `string` local.
round() {
    i = 0
    while i < 20 {
        string a = string.from_int(i)
        string b = string.pad_start(a, 4, 48)
        string c = string.new_with_length(string.concat(b, "xyz"), 4)
        string d = string.from_long(9000000000)
        string e = string.from_int_radix(255, 16)
        string f = string.from_char(65)
        string g = string.from_float(1.5)
        string h = string.pad_end("ab", 4, 46)
        string j = string.new("copy")
        string k = string.empty()
        string p = piece("alpha,beta", 1)
        l = list.new()
        list.add(l, a)
        list.add(l, f)
        string m = string.format("{}-{}", l)
        list.free(l)
        i = i + 1
    }
}

main() {
    string a = string.from_int(42)
    string b = string.pad_start(a, 5, 48)
    string c = string.new_with_length("abcdef", 3)
    string e = string.from_int_radix(255, 16)
    string f = string.from_char(65)
    string h = string.pad_end("ab", 4, 46)
    l = list.new()
    list.add(l, a)
    list.add(l, f)
    string m = string.format("{}-{}", l)
    list.free(l)
    println("${a} ${b} ${c} ${string.from_long(9000000000)} ${e} ${f}")
    println("${h} ${string.new("copy")} [${string.empty()}] ${m} ${piece("alpha,beta", 1)}")
    round()
    grown = mem.steady_growth(|| { round() }, 5)
    if !mem.heap_in_use_exact() || grown == 0 {
        println("no growth")
    } else {
        println("grown ${grown} bytes per round")
    }
}
AE
want="42 00042 abc 9000000000 ff A
ab.. copy [] 42-A beta
no growth"
for path in default nogcc; do
    cc=""
    [ "$path" = nogcc ] && cc="$CC_BIN -DAETHER_GCC_COMPAT=0"
    if ! AE_CC="$cc" "$AE" build "$tmp/typed.ae" -o "$tmp/typed_$path" >"$tmp/build.log" 2>&1; then
        echo "  [FAIL] std_strings_typed: the typed program did not build ($path):"
        grep -m6 -iE "error" "$tmp/build.log" | sed 's/^/        /'
        fail=1; continue
    fi
    got="$("$tmp/typed_$path" 2>&1 | tr -d '\r')"
    if [ "$got" != "$want" ]; then
        echo "  [FAIL] std_strings_typed: the typed program printed differently ($path)"
        printf 'got:\n%s\nwant:\n%s\n' "$got" "$want" | sed 's/^/        /'
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "  [PASS] std_strings_typed: std's string results are strings the caller owns (no growth), array_get outlives its array, new_with_length copies a string's characters, and a ptr is refused in an interpolation and a print, on both C paths"
fi
exit "$fail"
