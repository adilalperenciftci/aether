#!/bin/sh
# heap.new / heap.free across function boundaries (#1860).
#
# Two bugs met here. `return heap.new(T)` outside main lost the node's pointer
# type and fell back to calloc(1, sizeof(void)) -- a ONE BYTE allocation for
# the whole struct, so field writes ran past the end of it. And `b.name = ...`
# on a box another function made was a bare store, so heap.free released
# nothing and the string leaked.
#
# The allocation size is asserted in the generated C; the ownership by
# prog.ae's own heap growth, where the heap count is exact.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT
cd "$TMPDIR"

cat > main.ae <<'AEEOF'
import std.heap
import std.string

struct Box { name: string }

build_box() -> *Box { return heap.new(Box) }
dispose(b: *Box) { heap.free(b) }

main() {
    b = build_box()
    b.name = string.copy("hello")
    println("${b.name}")
    dispose(b)
}
AEEOF

if ! "$AETHERC" main.ae out.c > gen.log 2>&1; then
    echo "  [FAIL] heap_box_across_functions: codegen failed"
    cat gen.log
    exit 1
fi

if grep -q "sizeof(void)" out.c; then
    echo "  [FAIL] heap_box_across_functions: heap.new allocated sizeof(void), not the struct"
    exit 1
fi
if ! grep -q "sizeof(Box)" out.c; then
    echo "  [FAIL] heap_box_across_functions: no sizeof(Box) allocation emitted"
    exit 1
fi

if ! "$AE" build main.ae -o prog > build.log 2>&1; then
    echo "  [FAIL] heap_box_across_functions: build failed"
    cat build.log
    exit 1
fi
out="$(./prog)"
if [ "$out" != "hello" ]; then
    echo "  [FAIL] heap_box_across_functions: got '$out', want 'hello'"
    exit 1
fi
if ! "$AE" build "$SCRIPT_DIR/prog.ae" -o grow > grow.log 2>&1; then
    echo "  [FAIL] heap_box_across_functions: prog.ae did not build"
    cat grow.log
    exit 1
fi
if ! ./grow > grow.txt 2>&1; then
    echo "  [FAIL] heap_box_across_functions: the box's string leaked or was freed twice"
    sed 's/^/        /' grow.txt | head -4
    exit 1
fi

# Freed exactly once, where a leak checker is available: leaks(1) on macOS,
# where the heap count is not exact and the program cannot measure itself.
if [ "$(uname -s)" = Darwin ] && command -v leaks >/dev/null 2>&1; then
    if ! MallocStackLogging=1 leaks --atExit -- ./grow > ./grow.leaks 2>&1; then
        if grep -qE "[1-9][0-9]* leak(s)? for" ./grow.leaks; then
            echo "  [FAIL] heap_box_across_functions: a string leaked"
            grep -E "leaks? for" ./grow.leaks | sed 's/^/        /' | head -3
            exit 1
        fi
    fi
fi

echo "  [PASS] heap_box_across_functions: the box is sized right and owns its string field"
