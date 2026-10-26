#!/bin/sh
# Regression (#3177): spawn_sandboxed finds libaether_sandbox.so from a
# program that is not in build/.
#
# The library was looked for only beside the running program and in
# ../build/ from it. A program `ae run` builds lives in the build cache and
# one an installed toolchain builds lives anywhere, so neither found it:
# spawn_sandboxed printed "cannot find libaether_sandbox.so" and returned -1
# without starting the child. The lookup is now one, shared with the contrib
# process hosts: AETHER_SANDBOX_PRELOAD, beside the program, then lib/aether/,
# lib/ and build/ under AETHER_HOME (which ae sets for every program it
# runs) and under the program's directory's parent.
#
# Each case starts `cat` on a file under grants, from a program outside
# build/. A child that read the file printed it; one held to grants that do
# not cover it is refused by the preloaded library, which shows the library
# was really there.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

case "$(uname -s 2>/dev/null)" in
    Linux|FreeBSD) ;;
    *)
        echo "  [SKIP] sandbox_preload_lookup: spawn_sandboxed is Linux and FreeBSD only"
        exit 0 ;;
esac
if [ ! -x "$AE" ]; then
    echo "  [SKIP] sandbox_preload_lookup: ae not built"
    exit 0
fi
if [ ! -f "$ROOT/build/libaether_sandbox.so" ]; then
    echo "  [SKIP] sandbox_preload_lookup: build/libaether_sandbox.so not built"
    exit 0
fi

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export AETHER_CACHE_DIR="$TMP/cache"

printf 'the secret\n' > "$TMP/data.txt"
cat > "$TMP/launch.ae" <<'EOF'
import std.os
import std.sandbox

// launch <file> <pattern>: cat <file> under a grant to read <pattern>.
main() {
    file = os.args_get(1)
    pattern = os.args_get(2)
    reader = sandbox.new("reader") {
        grant_fs_read(pattern)
    }
    defer sandbox.free(reader)
    rc = spawn_sandboxed(reader, "cat", file)
    println("rc=${rc}")
}
EOF

fail=0

# expect LABEL WANT OUTPUT: OUTPUT holds WANT.
expect() {
    if printf '%s\n' "$3" | grep -qF -- "$2"; then
        echo "  [PASS] $1"
    else
        echo "  [FAIL] $1: expected \"$2\" in:"
        printf '%s\n' "$3" | sed 's/^/        /' | head -10
        fail=1
    fi
}

# 1. `ae run` from outside the tree: the binary is in the build cache, and
#    ae's AETHER_HOME (this tree) has the library in build/.
out="$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run launch.ae -- "$TMP/data.txt" "$TMP/data.txt" 2>&1)"
expect "ae run from outside build/: the child runs, and reads its file" "the secret" "$out"
expect "ae run from outside build/: the child exits 0" "rc=0" "$out"

out="$(cd "$TMP" && AETHER_HOME="$ROOT" "$AE" run launch.ae -- "$TMP/data.txt" "$TMP/nothing/*" 2>&1)"
if printf '%s\n' "$out" | grep -q "the secret"; then
    echo "  [FAIL] a grant that does not cover the file: the child read it anyway"
    printf '%s\n' "$out" | sed 's/^/        /' | head -10
    fail=1
else
    expect "a grant that does not cover the file: the preloaded library refuses it" "rc=1" "$out"
fi

# 2. A program installed in <prefix>/bin, with no AETHER_HOME: the library
#    is in <prefix>/lib/aether/, where install.sh puts it.
if ! (cd "$TMP" && AETHER_HOME="$ROOT" "$AE" build launch.ae -o launch) > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] the launcher does not build:"
    sed 's/^/        /' "$TMP/build.log" | head -10
    exit 1
fi
mkdir -p "$TMP/prefix/bin" "$TMP/prefix/lib/aether" "$TMP/elsewhere"
cp "$TMP/launch" "$TMP/prefix/bin/launch"
cp "$ROOT/build/libaether_sandbox.so" "$TMP/prefix/lib/aether/"
out="$(cd "$TMP/elsewhere" && env -u AETHER_HOME -u AETHER_SANDBOX_PRELOAD "$TMP/prefix/bin/launch" "$TMP/data.txt" "$TMP/data.txt" 2>&1)"
expect "an installed program finds <prefix>/lib/aether/" "rc=0" "$out"

# 3. AETHER_SANDBOX_PRELOAD names the library anywhere else.
mkdir -p "$TMP/alone" "$TMP/libs"
cp "$TMP/launch" "$TMP/alone/launch"
cp "$ROOT/build/libaether_sandbox.so" "$TMP/libs/"
out="$(cd "$TMP" && env -u AETHER_HOME AETHER_SANDBOX_PRELOAD="$TMP/libs/libaether_sandbox.so" "$TMP/alone/launch" "$TMP/data.txt" "$TMP/data.txt" 2>&1)"
expect "AETHER_SANDBOX_PRELOAD names it" "rc=0" "$out"

# 4. Nowhere: the call says where it looked, and starts no child.
out="$(cd "$TMP" && env -u AETHER_HOME -u AETHER_SANDBOX_PRELOAD "$TMP/alone/launch" "$TMP/data.txt" "$TMP/data.txt" 2>&1)"
expect "a missing library is named with the places looked at" "cannot find libaether_sandbox.so (looked at: $TMP/alone/libaether_sandbox.so" "$out"
expect "and the child is not started" "rc=-1" "$out"

exit $fail
