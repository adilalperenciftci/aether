#!/bin/sh
# Regression for #2729: a diagnostic about a function merged in from a module
# names it as the source spells it, `checks.shell`, not by its merged C name
# `checks_shell`.
#
# A module's functions are renamed `<ns>_<name>` when they are merged into the
# importing program. The effect-tag error (an `@pure` function reaching an
# `os` call) and the always-false `requires` error printed that C name, which
# appears nowhere in the source. The missing-return error already mapped it
# back; the three now share one helper.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] effect_tag_names_source: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/lib"
cat > "$TMP/lib/checks.ae" <<'AE'
import std.os

exports (shell, never)

@pure
shell() -> int {
    return os.system("echo hi")
}

never(n: int) -> int
    requires 1 > 2
{
    return n
}
AE

cat > "$TMP/main.ae" <<'AE'
import checks

main() {
    println("${checks.shell()} ${checks.never(1)}")
}
AE

out=$(cd "$TMP" && AETHER_LIB_DIR="$TMP/lib" "$AE" check main.ae 2>&1)

case "$out" in
    *"function 'checks.shell' is declared"*) ;;
    *) echo "  [FAIL] the effect-tag error does not name 'checks.shell':"
       echo "$out" | sed 's/^/        /'; exit 1 ;;
esac

case "$out" in
    *"no call to 'checks.never' can ever satisfy it"*) ;;
    *) echo "  [FAIL] the always-false requires error does not name 'checks.never':"
       echo "$out" | sed 's/^/        /'; exit 1 ;;
esac

# The merged C names appear nowhere in what the user reads.
case "$out" in
    *checks_shell*|*checks_never*)
       echo "  [FAIL] a diagnostic names a merged C name:"
       echo "$out" | sed 's/^/        /'; exit 1 ;;
esac

# The program's own function keeps its own name.
cat > "$TMP/own.ae" <<'AE'
import std.os

@pure
shell() -> int {
    return os.system("echo hi")
}

main() {
    println("${shell()}")
}
AE

out=$(cd "$TMP" && "$AE" check own.ae 2>&1)
case "$out" in
    *"function 'shell' is declared"*) ;;
    *) echo "  [FAIL] the program's own function is not named 'shell':"
       echo "$out" | sed 's/^/        /'; exit 1 ;;
esac

echo "  [PASS] effect_tag_names_source: diagnostics name a module function as the source does"
