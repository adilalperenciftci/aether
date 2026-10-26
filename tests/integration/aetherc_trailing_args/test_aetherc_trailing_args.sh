#!/bin/sh
# Regression (#3182): aetherc refuses an argument after its positionals.
#
# aetherc reads its options before the input and the output, and took
# whatever followed them in silence: `aetherc main.ae out.c --lib vendor`
# compiled without vendor, and the caller never knew (`ae help` lost every
# --lib that way, #3183). Each such argument is now an error naming it,
# with the command as it should be written, and nothing is compiled. The
# same options before the input still work, and `aetherc in.ae -o out.c`
# keeps its own message.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AETHERC" ] && [ ! -x "$AETHERC.exe" ]; then
    echo "  [SKIP] aetherc_trailing_args: aetherc not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

mkdir -p vendor/greet
cat > vendor/greet/module.ae <<'EOF'
exports(hello)

hello() -> string {
    return "hello"
}
EOF
cat > main.ae <<'EOF'
import greet

main() {
    println(greet.hello())
}
EOF

fail=0

# refused LABEL WANT ARGS...: aetherc ARGS fails, says WANT, writes no out.c.
refused() {
    label="$1"
    want="$2"
    shift 2
    rm -f out.c
    out="$("$AETHERC" "$@" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -qF -- "$want" && [ ! -f out.c ]; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label (exit $rc, out.c $( [ -f out.c ] && echo written || echo absent )):"
        printf '%s\n' "$out" | sed 's/^/        /' | head -8
        fail=1
    fi
}

refused "an option after the output" \
    "Error: unexpected argument '--lib' after the output; options go before the input:" \
    main.ae out.c --lib vendor
refused "the message gives the command as it should be" \
    " --lib vendor main.ae out.c" \
    main.ae out.c --lib vendor
refused "a third positional" \
    "Error: unexpected argument 'extra.c' after the output" \
    main.ae out.c extra.c
refused "an option after the input of a mode that writes nothing" \
    "Error: unexpected argument '--lib' after the input; options go before the input:" \
    --check main.ae --lib vendor
refused "-o keeps its own message" \
    "is not an output path" \
    main.ae -o out.c

rm -f out.c
if "$AETHERC" --lib vendor main.ae out.c > build.log 2>&1 && [ -f out.c ]; then
    echo "  [PASS] the same option before the input compiles"
else
    echo "  [FAIL] aetherc --lib vendor main.ae out.c:"
    sed 's/^/        /' build.log | head -8
    fail=1
fi
if "$AETHERC" --check --lib vendor main.ae > check.log 2>&1; then
    echo "  [PASS] a mode that writes nothing takes its input alone"
else
    echo "  [FAIL] aetherc --check --lib vendor main.ae:"
    sed 's/^/        /' check.log | head -8
    fail=1
fi

exit $fail
