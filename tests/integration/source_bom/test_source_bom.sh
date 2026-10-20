#!/bin/sh
# Regression (#2999): a UTF-8 byte order mark starting a source file.
#
# A file saved with a BOM (EF BB BF), as Windows editors write it, failed
# with E0100 and the BOM's first byte for a message, printed as garbage. The
# mark is no part of the program's text: the lexer, the formatter and `ae`'s
# line scans of a source file start after it. So a BOM file builds and runs,
# an imported module with one does too, `ae check` passes it, and `ae fmt`
# keeps the mark where it is. A BOM inside the file, a typographic quote and
# bytes that are not UTF-8 are E0100 naming the character, and a character
# the lexer stops at inside an imported module is reported with that message
# rather than as "Expected statement in block".

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
AETHERC="$ROOT/build/aetherc"

if [ ! -x "$AE" ]; then
    echo "  [SKIP] source_bom: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
BOM='\357\273\277'

# A program that starts with a BOM, importing a module that starts with one.
mkdir -p "$TMP/app/lib/twice"
printf "${BOM}exports (twice)\n\ntwice(n: int) -> int {\n    return n * 2\n}\n" \
    > "$TMP/app/lib/twice/module.ae"
printf "${BOM}import twice\n\nmain() {\n    println(\"bom \${twice.twice(21)}\")\n}\n" \
    > "$TMP/app/main.ae"

out="$(cd "$TMP/app" && "$AE" run main.ae 2>&1)"
if [ "$out" = "bom 42" ]; then
    echo "  [PASS] a BOM file importing a BOM module builds and runs"
else
    echo "  [FAIL] BOM program: expected 'bom 42', got:"
    printf '%s\n' "$out" | sed 's/^/        /' | head -10
    fail=1
fi

if (cd "$TMP/app" && "$AE" check main.ae) >"$TMP/check.log" 2>&1; then
    echo "  [PASS] ae check takes a BOM file"
else
    echo "  [FAIL] ae check refused a BOM file:"
    sed 's/^/        /' "$TMP/check.log" | head -10
    fail=1
fi

# ae fmt: a formatted BOM file is formatted; an unformatted one is formatted
# with its BOM kept first.
if "$AE" fmt --check "$TMP/app/main.ae" >"$TMP/fmt.log" 2>&1; then
    echo "  [PASS] ae fmt --check passes a formatted BOM file"
else
    echo "  [FAIL] ae fmt --check reported a formatted BOM file:"
    sed 's/^/        /' "$TMP/fmt.log" | head -5
    fail=1
fi
printf "${BOM}main()   {\nprintln(1)\n}\n" > "$TMP/messy.ae"
"$AE" fmt "$TMP/messy.ae" >/dev/null 2>&1
printf "${BOM}main() {\n    println(1)\n}\n" > "$TMP/messy.want"
if [ "$(od -An -c "$TMP/messy.ae")" = "$(od -An -c "$TMP/messy.want")" ]; then
    echo "  [PASS] ae fmt formats a BOM file and keeps the BOM"
else
    echo "  [FAIL] ae fmt on a BOM file gave:"
    od -c "$TMP/messy.ae" | head -5 | sed 's/^/        /'
    fail=1
fi

# refuse NAME WHERE MESSAGE: $TMP/NAME.ae fails with one E0100 containing
# MESSAGE at WHERE (line:column).
refuse() {
    name="$1"; where="$2"; msg="$3"
    out="$(cd "$TMP" && "$AETHERC" "$name.ae" "$TMP/$name.c" 2>&1)"
    if [ $? -eq 0 ]; then
        echo "  [FAIL] $name: compiled"
        fail=1
        return
    fi
    first=$(printf '%s\n' "$out" | grep -a -m1 '^error')
    at=$(printf '%s\n' "$out" | grep -a -m1 -- '-->' | sed 's/.*\.ae://')
    case "$first" in
        "error[E0100]: "*"$msg"*) ;;
        *)
            echo "  [FAIL] $name: expected E0100 with \"$msg\", got: $first"
            fail=1
            return
            ;;
    esac
    if [ "$at" != "$where" ]; then
        echo "  [FAIL] $name: reported at $at, expected $where"
        fail=1
        return
    fi
    echo "  [PASS] $name"
}

printf "main() {\n    x = 1 ${BOM}+ 2\n    println(x)\n}\n" > "$TMP/bom_inside.ae"
refuse bom_inside 2:11 'a byte order mark (U+FEFF) is allowed only at the start of the file'

printf 'main() {\n    s = \342\200\234hi\342\200\235\n    println(s)\n}\n' > "$TMP/smart_quote.ae"
refuse smart_quote 2:9 'unexpected character'
if ! printf '%s\n' "$out" | grep -a -q 'U+201C'; then
    echo "  [FAIL] smart_quote: the message does not name U+201C"
    fail=1
fi

printf 'main() {\n    x = 1 \200\n}\n' > "$TMP/not_utf8.ae"
refuse not_utf8 2:11 'invalid UTF-8 in the source (byte 0x80)'

mkdir -p "$TMP/lib/dollar"
printf 'exports (f)\n\nf(n: int) -> int {\n    return n $ 3\n}\n' > "$TMP/lib/dollar/module.ae"
printf 'import dollar\n\nmain() {\n    println(dollar.f(1))\n}\n' > "$TMP/module_char.ae"
refuse module_char 4:14 "unexpected character '\$'"

exit $fail
