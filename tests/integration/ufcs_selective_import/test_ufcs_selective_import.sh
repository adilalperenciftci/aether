#!/bin/sh
# UFCS (#928/#934) on a SELECTIVELY imported function. With
# `import fluent (plus)`, `g.plus(2)` on a local resolved `plus` as the bare
# name the selective import makes visible, and was rewritten after the pass
# that renames such a call to its qualified `fluent.plus`; codegen then
# emitted `plus(g, 2)`, an undeclared C function (a link/compile error), not
# `fluent_plus(g, 2)`. aether-ui's DSL imports its surface selectively, so
# its chained modifiers (`title.style_font_size(20)`) hit this.
#
# Acceptance: compiles, links, runs, prints exactly "7", "cb 5", "7".

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

out=$( cd "$SCRIPT_DIR" && AETHER_HOME="" "$AE" run main.ae 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "  [FAIL] ufcs_selective_import: program errored (rc=$rc)"
    echo "$out" | head -20 | sed 's/^/          /'
    exit 1
fi

got=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tr '\n' '|' | sed 's/|$//')
if [ "$got" != "7|cb 5|7" ]; then
    echo "  [FAIL] ufcs_selective_import: expected '7|cb 5|7', got '$got'"
    echo "$out" | head -20 | sed 's/^/          /'
    exit 1
fi

echo "  [PASS] ufcs_selective_import: UFCS on a selectively imported function"
exit 0
