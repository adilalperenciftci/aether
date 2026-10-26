#!/bin/sh
# Regression (#3181): a project's imports resolve the same from any
# directory the command is typed in.
#
# `ae run app/` and `ae build app/` pointed the source into app/ but
# compiled from the caller's directory, so `import greet` (app/lib/greet)
# was "unresolved import 'greet': no module of that name was found in src/,
# the project root, and installed packages", a message naming no directory
# at all. `ae run` and `ae check` from app/src failed the same way, while
# `ae build` from there worked (it entered the project root). Now each one
# compiles from the project root, and `ae run` still starts the program in
# the directory the command was typed in (#2148): the program reads
# ./where.txt from there. An import that really is missing names every
# directory searched.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] project_dir_imports: ae not built"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AETHER_HOME="$ROOT"
# A cache of the test's own: the runs below must compile, not reuse a
# binary another checkout built from a same-looking source.
export AETHER_CACHE_DIR="$TMP/cache"

mkdir -p "$TMP/app/src" "$TMP/app/lib/greet" "$TMP/elsewhere"
cat > "$TMP/app/aether.toml" <<'EOF'
[package]
name = "app"
version = "0.1.0"

[[bin]]
name = "app"
path = "src/main.ae"
EOF
cat > "$TMP/app/lib/greet/module.ae" <<'EOF'
exports(hello)

hello(name: string) -> string {
    return "hello, ${name}"
}
EOF
cat > "$TMP/app/src/main.ae" <<'EOF'
import std.fs
import std.string
import greet

main() {
    where, _ = fs.read("where.txt")
    println("${greet.hello("app")} (run in ${string.trim(where)})")
}
EOF
printf 'elsewhere\n' > "$TMP/elsewhere/where.txt"
printf 'src\n' > "$TMP/app/src/where.txt"
printf 'the project root\n' > "$TMP/app/where.txt"

fail=0

# expect LABEL WANT DIR CMD...: run CMD in DIR; its output must be WANT.
expect() {
    label="$1"
    want="$2"
    dir="$3"
    shift 3
    got="$(cd "$dir" && "$@" 2>&1)"
    if [ "$got" = "$want" ]; then
        echo "  [PASS] $label"
    else
        echo "  [FAIL] $label: expected \"$want\", got:"
        printf '%s\n' "$got" | sed 's/^/        /' | head -12
        fail=1
    fi
}

expect "ae run <dir> from another directory" \
    "hello, app (run in elsewhere)" "$TMP/elsewhere" "$AE" run ../app
expect "ae run from the project's src/" \
    "hello, app (run in src)" "$TMP/app/src" "$AE" run
expect "ae run main.ae from the project's src/" \
    "hello, app (run in src)" "$TMP/app/src" "$AE" run main.ae
expect "ae run from the project root" \
    "hello, app (run in the project root)" "$TMP/app" "$AE" run

out="$(cd "$TMP/elsewhere" && "$AE" build ../app -o built 2>&1)"
if [ -x "$TMP/elsewhere/built" ] || [ -x "$TMP/elsewhere/built.exe" ]; then
    BIN="$TMP/elsewhere/built"
    [ -x "$BIN.exe" ] && BIN="$BIN.exe"
    expect "ae build <dir> -o, from another directory, writes there" \
        "hello, app (run in elsewhere)" "$TMP/elsewhere" "$BIN"
else
    echo "  [FAIL] ae build ../app -o built: no binary in the directory it was typed in:"
    printf '%s\n' "$out" | sed 's/^/        /' | head -12
    fail=1
fi

if (cd "$TMP/app/src" && "$AE" check main.ae) > "$TMP/check.log" 2>&1; then
    echo "  [PASS] ae check main.ae from the project's src/"
else
    echo "  [FAIL] ae check main.ae from the project's src/:"
    sed 's/^/        /' "$TMP/check.log" | head -12
    fail=1
fi

# A module that is nowhere: the error names the project's own directories.
mkdir -p "$TMP/bad/src"
cat > "$TMP/bad/aether.toml" <<'EOF'
[package]
name = "bad"
version = "0.1.0"
EOF
cat > "$TMP/bad/src/main.ae" <<'EOF'
import nowhere

main() {
    nowhere.go()
}
EOF
out="$(cd "$TMP/elsewhere" && "$AE" run ../bad 2>&1)"
line="$(printf '%s\n' "$out" | grep -m1 "unresolved import 'nowhere'")"
case "$line" in
    *"bad/lib, "*"bad/src, "*"bad (where the compile ran), "*"bad/src (beside the importing file), and the installed packages"*)
        echo "  [PASS] a missing module's error names each directory searched"
        ;;
    *)
        echo "  [FAIL] missing module: the error does not name the project's directories:"
        printf '%s\n' "$out" | sed 's/^/        /' | head -8
        fail=1
        ;;
esac

exit $fail
