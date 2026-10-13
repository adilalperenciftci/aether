#!/bin/sh
# A slice of a function's own storage must not outlive the function (E0800).
#
# An array literal in a slice slot and a function's own fixed-size array
# live in its frame. A slice of either that left the function viewed memory
# the next call reused: `gs = [11, 22, 33]` in `fill()`, then a call that
# fills its own frame, printed `first 0` for `gs[0]`. A module-level `T[]`
# could not hold even the empty slice before #2785, so this came with it;
# a returned slice of a local array dangled before that too. Each way a view
# can leave the frame is refused at the value that leaves: a return, a store
# to a module-level `var`, a store to a field of something the function did
# not make for itself, and a closure that captured such a slice. A slice used
# while the function runs, passed down, or of a slice parameter or a `make`
# buffer, compiles and runs as before. A fixed-size array parameter is the
# function's own copy, so a slice of it is refused too. What a name holds
# where it leaves decides: one re-bound to a `make` buffer before it leaves
# is no view any more, when it is on every path to the exit, and so is one a
# call of a local closure re-binds on every path through its body.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] slice_escape: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# refused <name> <line:col> <text>: `ae check` refuses <name>.ae with E0800
# at that position, its message containing <text>.
refused() {
    name="$1"; at="$2"; text="$3"
    out=$(cd "$TMP" && "$AE" check "$name.ae" 2>&1)
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $name: accepted"
        echo "$out" | sed 's/^/        /'
        fails=$((fails + 1)); return
    fi
    case "$out" in
        *"error[E0800]"*"$text"*"$name.ae:$at"*) ;;
        *) echo "  [FAIL] $name: not E0800 \"$text\" at $at:"
           echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)) ;;
    esac
}

cat > "$TMP/global_literal.ae" <<'AE'
var gs: int[] = null

fill() {
    gs = [11, 22, 33]
}

main() {
    fill()
    println("${gs.len}")
}
AE
refused global_literal 4:10 "the module-level \`gs\` is given a slice of the storage of 'fill' (an array literal)"

cat > "$TMP/global_array.ae" <<'AE'
var gs: int[] = null

fill() {
    arr = [5, 6, 7]
    gs = arr
}

main() {
    fill()
    println("${gs.len}")
}
AE
refused global_array 5:10 "the module-level \`gs\` is given a slice of the storage of 'fill' (the array \`arr\`)"

cat > "$TMP/return_literal.ae" <<'AE'
lit() -> int[] {
    return [1, 2, 3]
}

main() {
    println("${lit().len}")
}
AE
refused return_literal 2:12 "'lit' returns a slice of its own storage (an array literal)"

cat > "$TMP/return_local.ae" <<'AE'
loc() -> int[] {
    let a: int[3] = [4, 5, 6]
    s = a[0..2]
    return s
}

main() {
    println("${loc().len}")
}
AE
refused return_local 4:12 "'loc' returns a slice of its own storage (\`s\`, which holds a slice of it)"

cat > "$TMP/field.ae" <<'AE'
extern malloc(n: long) -> ptr

struct Bag {
    xs: int[]
}

fill(b: *Bag) {
    let a: int[3] = [7, 8, 9]
    b.xs = a
}

main() {
    b = malloc(sizeof(Bag)) as *Bag
    fill(b)
    println("${b.xs.len}")
}
AE
refused field 9:12 "a field of \`b\`, which outlives 'fill', is given a slice of its own storage (the array \`a\`)"

cat > "$TMP/struct_value.ae" <<'AE'
struct Bag {
    xs: int[]
}

wrap() -> Bag {
    let a: int[3] = [7, 8, 9]
    b = Bag { xs: a }
    return b
}

main() {
    println("${wrap().xs.len}")
}
AE
refused struct_value 8:12 "'wrap' returns a slice of its own storage (\`b\`, which holds a slice of it)"

cat > "$TMP/capture.ae" <<'AE'
counter() -> fn {
    let a: int[3] = [7, 8, 9]
    s = a[0..3]
    return || { return s.len }
}

main() {
    println("${call(counter())}")
}
AE
refused capture 4:12 "'counter' returns a slice of its own storage (a closure that captured a slice of it)"

cat > "$TMP/array_param.ae" <<'AE'
first_two(a: int[3]) -> int[] {
    return a[0..2]
}

main() {
    s = first_two([11, 22, 33])
    println("${s[0]} ${s[1]}")
}
AE
refused array_param 2:13 "'first_two' returns a slice of its own storage (the array parameter \`a\`, its own copy)"

cat > "$TMP/branch_keeps.ae" <<'AE'
pick(n: int, c: bool) -> int[] {
    arr = [1, 2, 3]
    let v: int[] = arr
    if c {
        v = make([]int, n)
    }
    return v
}

main() {
    println("${pick(2, true).len}")
}
AE
refused branch_keeps 7:12 "'pick' returns a slice of its own storage (\`v\`, which holds a slice of it)"

cat > "$TMP/loop_keeps.ae" <<'AE'
pick(n: int) -> int[] {
    arr = [1, 2, 3]
    let v: int[] = make([]int, n)
    i = 0
    while i < n {
        if i == 1 {
            break
        }
        v = arr
        i = i + 1
    }
    return v
}

main() {
    println("${pick(3).len}")
}
AE
refused loop_keeps 12:12 "'pick' returns a slice of its own storage (\`v\`, which holds a slice of it)"

# What stays in the frame, or views storage that outlives it, runs.
cat > "$TMP/stays.ae" <<'AE'
struct Bag {
    xs: int[]
}

total(xs: int[]) -> int {
    s = 0
    for i in 0..xs.len {
        s = s + xs[i]
    }
    return s
}

made(n: int) -> int[] {
    return make([]int, n)
}

local_use() -> int {
    let a: int[3] = [4, 5, 6]
    s = a[0..2]
    b = Bag { xs: a }
    k = || { return s.len }
    return total(a) + s.len + b.xs.len + call(k) + total([1, 2])
}

main() {
    m = made(4)
    println("stays ${m.len} ${local_use()}")
    free(m)
}
AE
out=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run stays.ae 2>&1)
case "$out" in
    *"stays 4 25"*) ;;
    *) echo "  [FAIL] stays: not \"stays 4 25\":"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

# A name re-bound to storage that outlives the frame before it leaves holds
# no view of the frame any more: what it holds where it leaves decides.
cat > "$TMP/rebound.ae" <<'AE'
struct Holder {
    data: int[]
    n: int
}

fill(n: int) -> int[] {
    arr = [1, 2, 3]
    let v: int[] = arr
    t = v[0] + v[1]
    v = make([]int, n)
    v[0] = t
    return v
}

keep(n: int) -> Holder {
    arr = [1, 2, 3]
    h = Holder { data: arr, n: 0 }
    h.n = h.data[1]
    h.data = make([]int, n)
    h.data[0] = h.n
    return h
}

both(n: int, c: bool) -> int[] {
    arr = [5, 6, 7]
    let v: int[] = arr
    k = v[2]
    if c {
        v = make([]int, n)
    } else {
        v = make([]int, n + 1)
    }
    v[0] = k
    return v
}

main() {
    s = fill(3)
    h = keep(4)
    b = both(2, false)
    println("rebound ${s[0]} ${s.len} ${h.data[0]} ${h.data.len} ${b[0]} ${b.len}")
    free(s)
    free(h.data)
    free(b)
}
AE
out=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run rebound.ae 2>&1)
case "$out" in
    *"rebound 3 3 2 4 7 3"*) ;;
    *) echo "  [FAIL] rebound: not \"rebound 3 3 2 4 7 3\":"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

# A call of a local closure that re-binds the name on every path through its
# body re-binds it there. One that may not re-bind it (only under an `if`,
# or after a `return` that may come first), a call that may not run, and a
# closure passed on, leave what the name held.
cat > "$TMP/closure_if.ae" <<'AE'
pick(n: int) -> int[] {
    arr = [1, 2, 3]
    let v: int[] = arr
    reset = || {
        if n > 0 {
            v = make([]int, 4)
        }
    }
    reset()
    return v
}

main() {
    println("${pick(1).len}")
}
AE
refused closure_if 10:12 "'pick' returns a slice of its own storage (\`v\`, which holds a slice of it)"

cat > "$TMP/call_maybe.ae" <<'AE'
pick(n: int) -> int[] {
    arr = [1, 2, 3]
    let v: int[] = arr
    reset = || {
        v = make([]int, 4)
    }
    if n > 0 {
        reset()
    }
    return v
}

main() {
    println("${pick(1).len}")
}
AE
refused call_maybe 10:12 "'pick' returns a slice of its own storage (\`v\`, which holds a slice of it)"

cat > "$TMP/closure_passed.ae" <<'AE'
keep(c: fn) {
}

pick(n: int) -> int[] {
    arr = [1, 2, 3]
    let v: int[] = arr
    reset = || {
        v = make([]int, 4)
    }
    keep(reset)
    reset()
    return v
}

main() {
    println("${pick(1).len}")
}
AE
refused closure_passed 12:12 "'pick' returns a slice of its own storage (\`v\`, which holds a slice of it)"

cat > "$TMP/closure_returns.ae" <<'AE'
pick(n: int) -> int[] {
    arr = [1, 2, 3]
    let v: int[] = arr
    reset = || {
        if n > 0 {
            return
        }
        v = make([]int, 4)
    }
    reset()
    return v
}

main() {
    println("${pick(1).len}")
}
AE
refused closure_returns 11:12 "'pick' returns a slice of its own storage (\`v\`, which holds a slice of it)"

cat > "$TMP/closure_rebinds.ae" <<'AE'
struct Holder {
    data: int[]
}

f() -> int[] {
    arr = [1, 2, 3]
    let v: int[] = arr
    reset = || {
        v = make([]int, 4)
    }
    reset()
    return v
}

g() -> Holder {
    arr = [1, 2, 3]
    h = Holder { data: arr }
    reset = || {
        h.data = make([]int, 6)
    }
    reset()
    return h
}

both(n: int) -> int[] {
    arr = [1, 2, 3]
    let v: int[] = arr
    reset = || {
        if n > 0 {
            v = make([]int, 2)
        } else {
            v = make([]int, 5)
        }
    }
    reset()
    return v
}

main() {
    a = f()
    h = g()
    b = both(0)
    println("closure ${a.len} ${h.data.len} ${b.len}")
    free(a)
    free(h.data)
    free(b)
}
AE
out=$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run closure_rebinds.ae 2>&1)
case "$out" in
    *"closure 4 6 5"*) ;;
    *) echo "  [FAIL] closure_rebinds: not \"closure 4 6 5\":"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

[ "$fails" -eq 0 ] || exit 1
echo "  [PASS] slice_escape: a slice of a function's own storage stays in it"
