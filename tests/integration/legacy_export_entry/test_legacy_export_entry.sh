#!/bin/sh
# A legacy `export f()` in the file being compiled is a definition like any
# other (#2699).
#
# The wrapper stayed in that file's tree, and most passes that walk its
# top-level definitions did not look through it. The type checker's third
# pass skipped an exported function: no unused-local (W1001) or
# unreachable-code (W1002) warning, no `@scoped` or Isolated[T] check. Its
# result type was never inferred, it had no C prototype, an `@pure` caller
# did not see what it reached, an exported clause left its set, an exported
# constant was undeclared in the C and an exported actor could not be
# spawned. The compiler now puts the declaration in the wrapper's place
# right after parsing; what an importer may name is read from the module's
# own parse, so it is unchanged.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ]; then
    echo "  [SKIP] legacy_export_entry: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail=0

# Every check of the third pass reaches an exported function.
cat > "$tmp/checks.ae" <<'AE'
import std.string

extern keep(p: string)

export idle_local(n: int) -> int {
    idle = 7
    return n + 1
}

export after_return(n: int) -> int {
    return n
    println("never")
}

export scoped_escape() {
    @scoped s = string.concat("a", "b")
    t = s
    keep(t)
}

export moved_twice() {
    let iso = isolate(7)
    let a = consume(iso)
    let b = consume(iso)
    println("${a} ${b}")
}

main() {
    println(idle_local(1))
    println(after_return(1))
}
AE

out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" check checks.ae 2>&1)"
for want in "unused variable 'idle'" "unreachable code after return" \
            "binding 's' escapes its block" "use of moved value 'iso'"; do
    if ! printf '%s' "$out" | grep -qF "$want"; then
        echo "  [FAIL] legacy_export_entry: an exported function was not checked: no \"$want\""
        fail=1
    fi
done

# An exported definition builds and runs as a plain one does.
cat > "$tmp/plain.ae" <<'AE'
export const LIMIT = 3

export struct Point {
    x: int
    y: int
}

message Bump {}

export actor Counter {
    state count = 0
    receive {
        Bump() -> { count = count + 1 }
    }
}

main() {
    println(twice(21))
    a, b = pair(4)
    println("${a} ${b}")
    println(fact(5))
    println(sum(Point { x: 1, y: 2 }))
    c = spawn(Counter())
    c ! Bump {}
    println("spawned")
}

// Defined after main, which calls it.
export twice(n: int) -> int {
    return n * 2
}

// No result type written: it is inferred from the return.
export pair(n: int) {
    return n, "x"
}

// One clause exported and one not: still one set.
export fact(0) -> int {
    return 1
}
fact(n: int) -> int {
    return n * fact(n - 1)
}

export sum(p: Point) -> int {
    return p.x + p.y + LIMIT
}
AE

got="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run plain.ae 2>&1 | tr -d '\r' | tr '\n' ' ')"
if [ "$got" != "42 4 x 120 6 spawned " ]; then
    echo "  [FAIL] legacy_export_entry: the program with exported definitions printed '$got'"
    fail=1
fi

# An `@pure` function sees what an exported callee reaches.
cat > "$tmp/effect.ae" <<'AE'
import std.os

export helper() -> int {
    return os.system("echo hi")
}

@pure
run() -> int {
    return helper()
}

main() {
    println(run())
}
AE

out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" check effect.ae 2>&1)"
if ! printf '%s' "$out" | grep -qF 'reaches a `os` operation'; then
    echo "  [FAIL] legacy_export_entry: an @pure function calling an exported helper that runs os.system was accepted"
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "  [PASS] legacy_export_entry: an exported definition is checked, inferred, declared and run as a plain one"
fi
exit $fail
