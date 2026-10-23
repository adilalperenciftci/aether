#!/bin/sh
# Regression (#3103): a module's own import names the file beside it, not
# one in the directory the compiler runs in.
#
# std.jsonpath's facade does `import parser` for std/jsonpath/parser.ae.
# The local-path search tried the current directory before the importing
# module's own, so a program built in a directory that has a parser.ae of
# its own (contrib/jq, which imports both packages in its tests) handed
# std.jsonpath that file: "'free_query' is not exported from module
# 'parser'". The same program built from the repository root worked. A
# module's own imports now look beside it first; the entry program's still
# look in the current directory (the project root) first.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] module_import_beside_itself: ae not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A parser of the program's own, in the directory the build runs in.
cat > "$tmp/parser.ae" <<'AE'
exports(parse)

parse(text: string) -> int {
    return 1
}
AE

cat > "$tmp/main.ae" <<'AE'
import std.json
import std.jsonpath
import parser

main() {
    doc, jerr = json.parse("{\"b\": [1, 2, 3]}")
    if jerr != "" {
        println("json: ${jerr}")
        return
    }
    r, err = jsonpath.query(doc, "$.b[*]")
    if err != "" {
        println("jsonpath: ${err}")
        return
    }
    println("matches=${jsonpath.result_size(r)} own=${parser.parse("x")}")
    jsonpath.free_result(r)
    json.free(doc)
}
AE

out="$(cd "$tmp" && AETHER_HOME="$ROOT" "$AE" run main.ae 2>&1 | tr -d '\r')"
if ! printf '%s\n' "$out" | grep -Fxq "matches=3 own=1"; then
    echo "  [FAIL] module_import_beside_itself: expected 'matches=3 own=1'"
    printf '%s\n' "$out" | tail -6 | sed 's/^/        /'
    exit 1
fi
echo "  [PASS] module_import_beside_itself: std.jsonpath's parser is its own, the program's is the program's"
