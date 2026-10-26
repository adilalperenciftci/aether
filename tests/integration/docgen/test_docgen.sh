#!/bin/sh
# tools/docgen over a fixture std tree (#3161). The export list is the
# `exports (` that starts a code line, not the first "exports" in a comment
# (std.http's header made `this` and `module` its exports), and nothing is
# cut to a fixed buffer: a long name, a long parameter list, a long doc block
# and a long module header come through whole, and a const's value keeps a
# `/` inside its string. docs/api is checked against docgen's own output by
# check-api-docs, so only a test like this one sees docgen being wrong.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CC="${CC:-cc}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || true' EXIT
fail() { echo "  [FAIL] docgen: $1"; exit 1; }

"$CC" -O2 -Wall "$ROOT/tools/docgen/docgen.c" -o "$tmp/docgen" 2>"$tmp/cc.log" \
    || { cat "$tmp/cc.log"; fail "docgen did not build"; }

mkdir -p "$tmp/std/demo" "$tmp/std/broken"
long_name="a_name_that_runs_well_past_the_hundred_and_twenty_seven_bytes_a_name_buffer_used_to_hold_before_it_was_split_into_two_exports_end"
long_doc=""
i=0
while [ $i -lt 400 ]; do long_doc="$long_doc word$i"; i=$((i + 1)); done
long_params=""
i=0
while [ $i -lt 90 ]; do long_params="${long_params}p$i: int, "; i=$((i + 1)); done
long_params="${long_params}last_param: string"
header_tail="the header ends here, past a thousand and twenty four bytes"
{
    echo "// std.demo - The fixture module. It re-exports nothing (this module)."
    i=0
    while [ $i -lt 40 ]; do echo "// A header line long enough to add up, number $i of forty, for the fixture."; i=$((i + 1)); done
    echo "// $header_tail."
    echo ""
    echo "exports("
    echo "    plain, $long_name, many, SEP, NOTE"
    echo ")"
    echo ""
    echo "// $long_doc END_OF_DOC"
    echo "plain(x: int) -> int {"
    echo "    return x"
    echo "}"
    echo ""
    echo "$long_name() -> int {"
    echo "    return 1"
    echo "}"
    echo ""
    echo "many($long_params) -> string {"
    echo "    return last_param"
    echo "}"
    echo ""
    echo "const SEP = \"a/b\""
    echo "const NOTE = 7 // a note"
} > "$tmp/std/demo/module.ae"

out="$tmp/api"
"$tmp/docgen" "$tmp/std" "$out" >"$tmp/run.log" 2>&1 || { cat "$tmp/run.log"; fail "docgen failed on a good tree"; }
page="$out/demo.html"
[ -f "$page" ] || fail "no page for the fixture module"

grep -q 'id="this"' "$page" && fail "a comment's \"(this module)\" became an export"
for name in plain many SEP NOTE; do
    grep -q "id=\"$name\"" "$page" || fail "the export $name is not documented"
done
grep -qF "id=\"$long_name\"" "$page" || fail "a 130-byte name was cut"
grep -q "END_OF_DOC" "$page" || fail "a long doc block was cut"
grep -qF "last_param: string" "$page" || fail "a long parameter list was cut"
grep -qF 'SEP = &quot;a/b&quot;' "$page" || fail "a const's string value was cut at its slash"
grep -qF 'NOTE = 7<' "$page" || fail "a const's trailing comment was kept"
grep -q '5 exports' "$out/index.html" || fail "the index does not count five exports"

# An export list that never closes fails the run, rather than documenting
# whatever followed it.
printf 'exports(\n    one, two\n\nconst one = 1\n' > "$tmp/std/broken/module.ae"
if "$tmp/docgen" "$tmp/std" "$tmp/api2" >"$tmp/run2.log" 2>&1; then
    fail "an unclosed exports ( list did not fail the run"
fi
grep -q "never closed" "$tmp/run2.log" || fail "the unclosed list's error does not say so"

echo "  [PASS] docgen"
