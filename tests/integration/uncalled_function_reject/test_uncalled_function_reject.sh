#!/bin/sh
# A function's name alone as a statement is an error at the name (#3188).
#
# It calls nothing. `serve { port(1) }`, a builder written without its
# `()`, read as the name `serve` and then a bare block: it compiled without
# a word, the block ran as a block and the builder never did. Qualified,
# `my_lib.serve { ... }` reported the block's setters as undefined
# functions instead. A trailing block goes after the parentheses
# (docs/closures-and-builder-dsl.md), and that form still builds and runs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
NAME=uncalled_function_reject

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] $NAME: $AE not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
export AETHER_HOME="$ROOT"
cd "$tmp" || exit 1

fail() {
    echo "  [FAIL] $NAME: $1"
    [ -n "$2" ] && [ -f "$2" ] && sed 's/^/        /' "$2" | head -20
    exit 1
}

# expect_reject <case> <file> <name> <line:col>: the file fails type checking
# with the error naming <name> at that place.
expect_reject() {
    if AETHER_LIB_DIR="$tmp/lib" "$AE" check "$2" > "$1.log" 2>&1; then
        fail "$1: the uncalled function was accepted" "$1.log"
    fi
    tr -d '\r' < "$1.log" > "$1.txt"
    grep -qF "'$3' is a function, and its name alone calls nothing: call it as $3()" "$1.txt" ||
        fail "$1: missing the error for '$3'" "$1.txt"
    grep -qF -- "--> $2:$4" "$1.txt" || fail "$1: not reported at $4" "$1.txt"
}

mkdir -p lib/my_lib
cat > lib/my_lib/module.ae <<'AE'
exports(serve, port)

builder serve() {
    println("serving")
}

port(n: int) {
    println("port ${n}")
}
AE

cat > bare.ae <<'AE'
builder serve() {
    println("serving")
}

main() {
    serve
}
AE
expect_reject bare bare.ae serve 6:5

cat > block.ae <<'AE'
builder serve() {
    println("serving")
}

port(n: int) {
    println("port ${n}")
}

main() {
    serve { port(1) }
}
AE
expect_reject block block.ae serve 10:5

cat > qualified.ae <<'AE'
import my_lib

main() {
    my_lib.serve { my_lib.port(9990) }
}
AE
expect_reject qualified qualified.ae my_lib.serve 4:5

# A block arm's last name is its value only in a match that gives a value
# (test_issue3037_match_function_value.ae); in a match used as a statement
# it calls nothing either.
cat > arm.ae <<'AE'
serve() {
    println("serving")
}

main() {
    k = 1
    match k {
        1 -> {
            serve
        }
        _ -> {}
    }
}
AE
expect_reject arm arm.ae serve 9:13

# The form the grammar means runs the block and then the builder.
cat > called.ae <<'AE'
builder serve() {
    println("serving")
}

port(n: int) {
    println("port ${n}")
}

main() {
    serve() { port(1) }
}
AE
"$AE" run called.ae > called.log 2>&1 || fail "serve() { ... } did not build and run" called.log
tr -d '\r' < called.log > called.txt
grep -qx "port 1" called.txt && grep -qx "serving" called.txt ||
    fail "serve() { ... } did not run the block and the builder" called.txt

echo "  [PASS] $NAME: a function's name alone is an error, bare and qualified; serve() { ... } runs"
exit 0
