#!/bin/sh
# Regression (#3116): in a module that defines its own `free`, `free(xs)` of
# a slice frees the slice with the builtin.
#
# The merger renames a module's own calls to its functions, so in a module
# defining `free(p: ptr)` (bignum.free, json.free) every `free(x)` was that
# function: a slice decayed to its pointer and the module read it as its own
# object, and the builtin, the one release of a `make` buffer, was out of
# reach. Now a slice argument goes to the builtin unless the module's own
# `free` takes a slice itself.
#
# 1. holder: free(p: ptr) frees a slice field and a temporary slice; the
#    program runs and every value is right.
# 2. takes_slice: the module's free(xs: int[]) takes the slice, so its own
#    body runs for it.
# 3. frees_view: `free` of a sub-slice in such a module is refused, as
#    everywhere else (#3072).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -x "$AE" ] || AE="$ROOT/build/ae.exe"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

cat > "$tmp/holder.ae" <<'AE'
exports(new, total, free)

struct Holder {
    xs: int[]
}

new(n: int) -> ptr {
    h = heap.new(Holder)
    h.xs = make([]int, n)
    i = 0
    while i < n {
        h.xs[i] = i + 1
        i = i + 1
    }
    return h as ptr
}

// Twice the sum, through a temporary slice the module frees.
total(p: ptr) -> int {
    h = p as *Holder
    tmp = make([]int, h.xs.len)
    sum = 0
    i = 0
    while i < h.xs.len {
        tmp[i] = h.xs[i] * 2
        sum = sum + tmp[i]
        i = i + 1
    }
    free(tmp)
    return sum
}

// The module's own free: a Holder, whose slice field the builtin frees.
free(p: ptr) {
    h = p as *Holder
    free(h.xs)
    heap.free(h)
}
AE

cat > "$tmp/takes_slice.ae" <<'AE'
exports(ints, free, freed)

var released = 0

ints(n: int) -> int[] {
    return make([]int, n)
}

// This module's free takes the slice itself, so a slice is its business.
// `@keep`: it takes the caller's buffer, which its scope exit releases.
free(xs: @keep int[]) {
    released = released + xs.len
}

freed() -> int {
    return released
}
AE

cat > "$tmp/main.ae" <<'AE'
import holder
import takes_slice

main() {
    h = holder.new(4)
    t = holder.total(h)
    holder.free(h)
    xs = takes_slice.ints(3)
    takes_slice.free(xs)
    println("total=${t} freed=${takes_slice.freed()}")
}
AE

out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run main.ae 2>&1 | tr -d '\r')"
if ! printf '%s\n' "$out" | grep -Fxq "total=20 freed=3"; then
    echo "  [FAIL] module_own_free_slice: expected 'total=20 freed=3'"
    printf '%s\n' "$out" | sed 's/^/    /' | head -12
    fail=1
fi

cat > "$tmp/frees_view.ae" <<'AE'
exports(drop, free)

drop(xs: int[]) {
    free(xs[1..])
}

free(p: ptr) {
    heap.free(p)
}
AE

cat > "$tmp/main_view.ae" <<'AE'
import frees_view

main() {
    xs = make([]int, 4)
    frees_view.drop(xs)
}
AE

out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" build main_view.ae -o main_view 2>&1 | tr -d '\r')"
if ! printf '%s\n' "$out" | grep -q "which owns nothing"; then
    echo "  [FAIL] module_own_free_slice: a free of a view in such a module was not refused"
    printf '%s\n' "$out" | sed 's/^/    /' | head -12
    fail=1
fi

[ $fail -eq 0 ] && echo "  [PASS] module_own_free_slice"
exit $fail
