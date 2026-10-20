#!/bin/sh
# `ae check` warns on a call that names its module twice (#2976 step 5,
# W1006): `json.json_free(v)` where `json.free(v)` is the same function. The
# tree was rewritten to the short form; the warning keeps the long form from
# coming back, and says how to rewrite: `ae fmt --short-names`. Only where
# the compiler resolves both spellings to one declaration: a long name with
# no short form (`sha3.sha3_256_hex`) is not reported, nor is a doubled call
# inside an imported module, and `ae build` stays quiet. Rewritten, the file
# checks clean.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
if [ ! -x "$AE" ]; then
    echo "  [SKIP] check_short_names: ae not built"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" || :' EXIT
export AETHER_HOME="$ROOT"
fail=0

# A module whose own body names itself twice: not the checked file's call.
mkdir -p "$tmp/tally"
cat > "$tmp/tally/module.ae" <<'AE'
exports(tally_count, twice)

tally_count() -> int {
    return 3
}

twice() -> int {
    return tally.tally_count() * 2
}
AE

cat > "$tmp/prog.ae" <<'AE'
import std.json
import std.string
import std.cryptography.md5
import std.cryptography.sha3
import tally

main() {
    v, _ = json.parse("[1,2]")
    println("${json.json_array_size(v)} ${string.string_length("abc")}")
    json.json_free(v)
    h = md5.md5_hex(string.bytes("a"))
    d = sha3.sha3_256_hex(string.bytes("a"))
    println("${h} ${string.length(d)} ${tally.twice()} ${tally.tally_count()}")
}
AE

(cd "$tmp" && "$AE" check prog.ae >"$tmp/check.log" 2>&1)
rc=$?
if [ $rc -ne 0 ]; then
    echo "  [FAIL] check_short_names: ae check failed (exit $rc)"
    sed 's/^/          /' "$tmp/check.log" | head -10
    fail=1
fi
for want in \
    "warning[W1006]: \`json.json_array_size\` names its module twice: \`json.array_size\` is the same function" \
    "warning[W1006]: \`string.string_length\` names its module twice: \`string.length\` is the same function" \
    "warning[W1006]: \`json.json_free\` names its module twice: \`json.free\` is the same function" \
    "warning[W1006]: \`md5.md5_hex\` names its module twice: \`md5.hex\` is the same function" \
    "warning[W1006]: \`tally.tally_count\` names its module twice: \`tally.count\` is the same function" \
    "run \`ae fmt --short-names prog.ae\`" \
    "OK: 5 warning(s)"; do
    if ! grep -qF -- "$want" "$tmp/check.log"; then
        echo "  [FAIL] check_short_names: ae check does not say: $want"
        sed 's/^/          /' "$tmp/check.log" | head -24
        fail=1
    fi
done
if grep -q "sha3_256_hex.*names its module twice" "$tmp/check.log"; then
    echo "  [FAIL] check_short_names: a name with no short form was reported"
    fail=1
fi
if [ "$(grep -c "W1006" "$tmp/check.log")" != "5" ]; then
    echo "  [FAIL] check_short_names: not exactly 5 W1006 warnings (the module's own call is not the file's)"
    fail=1
fi

(cd "$tmp" && "$AE" build prog.ae -o prog >"$tmp/build.log" 2>&1)
if grep -q "W1006" "$tmp/build.log"; then
    echo "  [FAIL] check_short_names: ae build reported W1006"
    fail=1
fi

(cd "$tmp" && "$AE" fmt --short-names prog.ae >/dev/null 2>&1)
(cd "$tmp" && "$AE" check prog.ae >"$tmp/after.log" 2>&1)
if grep -q "W1006" "$tmp/after.log" || ! grep -q "OK: no errors" "$tmp/after.log"; then
    echo "  [FAIL] check_short_names: the rewritten file does not check clean:"
    sed 's/^/          /' "$tmp/after.log" | head -10
    fail=1
fi

if [ $fail -eq 0 ]; then
    echo "  [PASS] check_short_names: ae check warns on each doubled module name (W1006) and names the rewrite"
fi
exit $fail
