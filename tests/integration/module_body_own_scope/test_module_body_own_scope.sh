#!/bin/sh
# A module's body resolves in its own scope (#3088): its own declarations,
# what it imports, std's builtins. It saw the program's functions and types
# too: pkg.user's `helper()` called the program's `helper()`, which pkg.user
# never imported, and a program's `struct frame` took the place of
# pkg.user's own import in `frame.SETS`. And a function of the module's own
# named like its import was renamed into the base of `frame.SETS`
# (`user_frame.SETS`). A module's call of a function it does not see is
# refused, and `frame.SETS` is its import's constant beside any function or
# type of that name, the program's or its own.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] module_body_own_scope: $AE not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AETHER_HOME="$ROOT"
fails=0

# frame: the module pkg.user imports, with a constant and a function.
mkdir -p "$TMP/lib/pkg/frame" "$TMP/lib/pkg/user"
cat > "$TMP/lib/pkg/frame/module.ae" <<'AE'
exports(
    SETS, twice,
)

const SETS = 3

twice(n: int) -> int {
    return n * 2
}
AE

# run_ok <name> <want>: main.ae with the pkg.user of the moment runs and
# prints <want>.
run_ok() {
    got=$(cd "$TMP" && "$AE" run main.ae 2>&1 | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -1)
    if [ "$got" != "$2" ]; then
        echo "  [FAIL] $1: expected '$2', got '$got'"
        (cd "$TMP" && "$AE" run main.ae 2>&1 | head -12 | sed 's/^/        /')
        fails=$((fails + 1))
    fi
}

# A program's struct of the import's name.
cat > "$TMP/lib/pkg/user/module.ae" <<'AE'
import pkg.frame

exports(
    sets,
)

sets() -> int {
    return frame.SETS + frame.twice(1)
}
AE
cat > "$TMP/main.ae" <<'AE'
import pkg.user

struct frame {
    w: int
}

main() {
    f = frame { w: 4 }
    println("${user.sets()} ${f.w}")
}
AE
run_ok program_struct "5 4"

# The module's own function named like its import.
cat > "$TMP/lib/pkg/user/module.ae" <<'AE'
import pkg.frame

exports(
    sets,
)

frame() -> int {
    return 10
}

sets() -> int {
    return frame.SETS + frame()
}
AE
cat > "$TMP/main.ae" <<'AE'
import pkg.user

main() {
    println("${user.sets()}")
}
AE
run_ok module_own_function "13"

# A module's call of a program function it never imported is refused.
cat > "$TMP/lib/pkg/user/module.ae" <<'AE'
exports(
    leak,
)

leak() -> int {
    return helper()
}
AE
cat > "$TMP/main.ae" <<'AE'
import pkg.user

helper() -> int {
    return 42
}

main() {
    println("${user.leak()}")
}
AE
out=$(cd "$TMP" && "$AE" check main.ae 2>&1 | tr -d '\r')
case "$out" in
    *"error"*"helper"*"lib/pkg/user/module.ae:6:"*) ;;
    *) echo "  [FAIL] program_function: pkg.user's helper() was not refused at its call"
       echo "$out" | sed 's/^/        /'
       fails=$((fails + 1)) ;;
esac

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] module_body_own_scope: a module sees its own declarations and imports, not the program's"
