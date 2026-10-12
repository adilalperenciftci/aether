#!/bin/sh
# Regression for #1946: a warning raised inside an IMPORTED module must name
# that module's file, not the importing one.
#
# A module's AST is merged into the importing program before the unused-variable
# pass runs, and that pass built its diagnostic with no filename. The renderer
# fell back to the active source context, which by then is the entry file again,
# so the warning named a file the variable is not in and printed that file's
# line N underneath as the snippet. When N was past the entry file's end there
# was no snippet at all: asn1/module.ae:613 was reported against a 175-line test
# file. The 56 stdlib warnings in #1942 all pointed at whatever imported them.
#
# Asserts the file, the line, the caret's snippet text, and that the ENTRY file
# is not named.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

[ -x "$AE" ] || { echo "  [SKIP] warning_names_declaring_file: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/lib"
cat > "$TMP/lib/mymod.ae" <<'AE'
exports (helper)

helper() -> int {
    unused_here = 42
    return 7
}
AE

# Deliberately longer than the module, so a wrong file still has a line 4 and
# the failure is a WRONG snippet rather than a missing one.
cat > "$TMP/main.ae" <<'AE'
import mymod

main() {
    println("${mymod.helper()}")
}
AE

out=$(cd "$TMP" && AETHER_LIB_DIR="$TMP/lib" "$AE" check main.ae 2>&1)

case "$out" in
    *"unused variable 'unused_here'"*) ;;
    *) echo "  [FAIL] the module's unused variable was not reported at all:"
       echo "$out" | sed 's/^/        /'; exit 1 ;;
esac

case "$out" in
    *mymod.ae:4:5*) ;;
    *) echo "  [FAIL] the warning does not name the declaring module at line 4:"
       echo "$out" | sed 's/^/        /'; exit 1 ;;
esac

# The snippet must be the module's line, not the importing file's.
case "$out" in
    *"unused_here = 42"*) ;;
    *) echo "  [FAIL] the snippet is not the module's source line:"
       echo "$out" | sed 's/^/        /'; exit 1 ;;
esac

# And the entry file must not be named as the location.
case "$out" in
    *"--> main.ae"*)
       echo "  [FAIL] the warning names the importing file:"
       echo "$out" | sed 's/^/        /'; exit 1 ;;
esac

# The rest of the third pass, the match-arm check and the effect check named
# the importing file too: they reported with no file after the second pass
# had stopped naming one. Each now names the module and the line in it.
cat > "$TMP/lib/checks.ae" <<'AE'
import std.string
import std.os

exports (after_return, twice_one, leak, moved, shell)

extern keep(p: string)

after_return(n: int) -> int {
    return n
    println("never")
}

twice_one(n: int) -> int {
    match n {
        1 -> { return 10 }
        1 -> { return 11 }
        _ -> { return 0 }
    }
}

leak() {
    @scoped s = string.concat("a", "b")
    t = s
    keep(t)
}

moved() {
    let iso = isolate(7)
    let a = consume(iso)
    let b = consume(iso)
    println("${a} ${b}")
}

@pure
shell() -> int {
    return os.system("echo hi")
}
AE

cat > "$TMP/main2.ae" <<'AE'
import checks

main() {
    println("${checks.after_return(1)}")
}
AE

out=$(cd "$TMP" && AETHER_LIB_DIR="$TMP/lib" "$AE" check main2.ae 2>&1)

for at in "checks.ae:10:" "checks.ae:16:" "checks.ae:23:" "checks.ae:30:" "checks.ae:35:"; do
    case "$out" in
        *"$at"*) ;;
        *) echo "  [FAIL] no diagnostic names $at (W1002, W1004, @scoped, Isolated[T], @pure in turn):"
           echo "$out" | sed 's/^/        /'; exit 1 ;;
    esac
done

case "$out" in
    *"--> main2.ae"*)
       echo "  [FAIL] a diagnostic in the module names the importing file:"
       echo "$out" | sed 's/^/        /'; exit 1 ;;
esac

echo "  [PASS] warning_names_declaring_file: a module's warnings and errors name the module"
