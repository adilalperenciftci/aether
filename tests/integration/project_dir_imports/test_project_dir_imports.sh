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
# directory searched, and a relative AETHER_CACHE_DIR or AETHER_LIB_DIR
# keeps meaning a directory where the command was typed.

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

# The environment's relative paths mean what they mean where the command
# was typed. Entering the project made a relative AETHER_CACHE_DIR a cache
# inside it, and a relative AETHER_LIB_DIR a directory of the project's.
rm -rf "$TMP/elsewhere/relcache" "$TMP/app/relcache"
expect "a relative AETHER_CACHE_DIR, from another directory" \
    "hello, app (run in elsewhere)" "$TMP/elsewhere" env AETHER_CACHE_DIR=relcache "$AE" run ../app
if [ -d "$TMP/elsewhere/relcache" ] && [ ! -d "$TMP/app/relcache" ]; then
    echo "  [PASS] the cache is where the command was typed, not in the project"
else
    echo "  [FAIL] a relative AETHER_CACHE_DIR: elsewhere/relcache $( [ -d "$TMP/elsewhere/relcache" ] && echo exists || echo missing ), app/relcache $( [ -d "$TMP/app/relcache" ] && echo exists || echo absent )"
    fail=1
fi

mkdir -p "$TMP/plain/src" "$TMP/elsewhere/vendor/shout"
cat > "$TMP/plain/aether.toml" <<'EOF'
[package]
name = "plain"
version = "0.1.0"
EOF
cat > "$TMP/plain/src/main.ae" <<'EOF'
import shout

main() {
    println(shout.loud("vendor"))
}
EOF
cat > "$TMP/elsewhere/vendor/shout/module.ae" <<'EOF'
exports(loud)

loud(s: string) -> string {
    return "${s}!"
}
EOF
expect "a relative AETHER_LIB_DIR names a directory where the command was typed" \
    "vendor!" "$TMP/elsewhere" env AETHER_LIB_DIR=vendor "$AE" run ../plain

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

# A diagnostic names its file from where the command was typed (#3215): the
# compile runs from the project root, and named it from there (`src/oops.ae`
# for the oops.ae typed in src/), a path that does not exist where the user
# stands.
cat > "$TMP/app/src/oops.ae" <<'EOF'
main() {
    x: int = "not a number"
}
EOF
out="$(cd "$TMP/app/src" && "$AE" check oops.ae 2>&1)"
loc="$(printf '%s\n' "$out" | grep -m1 -- '-->' | sed 's/^ *--> *//; s/:[0-9]*:[0-9]*$//')"
hint="$(printf '%s\n' "$out" | grep -m1 'hint: run `ae help')"
case "$loc|$hint" in
    "oops.ae|"*"ae help oops.ae"*)
        echo "  [PASS] a diagnostic names the file as typed in the project's subdirectory"
        ;;
    *)
        echo "  [FAIL] diagnostic path from app/src: '$loc', hint '$hint':"
        printf '%s\n' "$out" | sed 's/^/        /' | head -8
        fail=1
        ;;
esac
mkdir -p "$TMP/badtype/src"
cp "$TMP/bad/aether.toml" "$TMP/badtype/aether.toml"
cp "$TMP/app/src/oops.ae" "$TMP/badtype/src/main.ae"
out="$(cd "$TMP/elsewhere" && "$AE" run ../badtype 2>&1)"
loc="$(printf '%s\n' "$out" | grep -m1 -- '-->' | sed 's/^ *--> *//; s/:[0-9]*:[0-9]*$//')"
if [ "$loc" = "../badtype/src/main.ae" ]; then
    echo "  [PASS] a diagnostic names a named project's file from where the command was typed"
else
    echo "  [FAIL] diagnostic path for ae run ../badtype: '$loc':"
    printf '%s\n' "$out" | sed 's/^/        /' | head -8
    fail=1
fi

exit $fail
