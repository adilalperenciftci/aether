#!/bin/sh
# #2780: tests/scripts/contrib_build.sh never shows a reader a vendored
# sqlite veneer without the vendored libsqlite3.a it calls into.
#
# Tests in the sweep run the script while others link against build/contrib.
# It used to archive the veneer (compiled with AETHER_SQLITE_VENDORED, so it
# calls sqlite3_enable_load_extension) first and the vendored libsqlite3.a
# only after the SQLite amalgamation compiled, most of a minute on a fresh
# runner. A link in between resolved -lsqlite3 to macOS's system library,
# which has no such symbol, and the 0.807.0 and 0.808.0 macOS release builds
# failed on link_directive_build.
#
# The script builds sqlite into a directory of this test's own
# (CONTRIB_OUT), with a compiler that makes real objects quickly but takes
# 3 s over sqlite3.c, so the window is wide; the directory is watched
# throughout. Afterwards both archives and the manifest lines are there, and
# no staging directory is left.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
NAME=contrib_build_publish

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "  [FAIL] $NAME: $1"; exit 1; }

REAL_CC="${CC:-cc}"
command -v "$REAL_CC" >/dev/null 2>&1 || REAL_CC=gcc
command -v "$REAL_CC" >/dev/null 2>&1 || { echo "  [SKIP] $NAME: no C compiler"; exit 0; }
command -v ar >/dev/null 2>&1 || { echo "  [SKIP] $NAME: no ar"; exit 0; }

# The stand-in compiler: for `-c SRC -o OBJ` it compiles a one-line C file of
# its own to OBJ (a real object, so ar indexes it), waiting 3 s first when
# SRC is the amalgamation. Anything else (--version) goes to the real one.
printf 'int contrib_build_publish_probe;\n' > "$TMP/one.c"
cat > "$TMP/cc" <<EOF
#!/bin/sh
src=""; out=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -c) src="\$2"; shift ;;
        -o) out="\$2"; shift ;;
    esac
    shift
done
if [ -z "\$out" ]; then exec "$REAL_CC" --version; fi
case "\$src" in *sqlite3.c) sleep 3 ;; esac
exec "$REAL_CC" -c "$TMP/one.c" -o "\$out"
EOF
chmod +x "$TMP/cc"

OUT="$TMP/out"
mkdir -p "$OUT"
( cd "$ROOT" && CONTRIB_OUT="$OUT" CC="$TMP/cc" MODULES=sqlite \
    SQLITE_OBJ_CACHE_DIR="$TMP/cache" bash tests/scripts/contrib_build.sh ) \
    >"$TMP/build.log" 2>&1 &
build=$!

# Watch until the build ends: a veneer in place with no libsqlite3.a beside
# it is the state a link must never see.
seen=""
while kill -0 "$build" 2>/dev/null; do
    if [ -f "$OUT/libaether_sqlite.a" ] && [ ! -f "$OUT/libsqlite3.a" ]; then
        seen=1
    fi
    sleep 0.05
done
wait "$build"
rc=$?

if grep -q "amalgamation unavailable" "$TMP/build.log"; then
    echo "  [SKIP] $NAME: the SQLite amalgamation could not be fetched, so nothing is vendored"
    exit 0
fi
[ "$rc" -eq 0 ] || { sed 's/^/    /' "$TMP/build.log" | tail -15; fail "contrib_build.sh exited $rc"; }
[ -z "$seen" ] || fail "the vendored veneer was in place without libsqlite3.a while sqlite3.c compiled"
[ -f "$OUT/libsqlite3.a" ] || fail "no libsqlite3.a after the build"
[ -f "$OUT/libaether_sqlite.a" ] || fail "no libaether_sqlite.a after the build"
grep -qxF "$(printf 'sqlite3\tbuild/contrib/libsqlite3.a\tlibsqlite3.a')" "$OUT/MANIFEST" \
    || fail "the manifest has no vendored sqlite3 line: $(cat "$OUT/MANIFEST")"
grep -qxF "$(printf 'sqlite\tbuild/contrib/libaether_sqlite.a')" "$OUT/MANIFEST" \
    || fail "the manifest has no sqlite veneer line: $(cat "$OUT/MANIFEST")"
left=$(ls -A "$OUT" | grep '^\.stage\.' || :)
[ -z "$left" ] || fail "a staging directory was left behind: $left"
for f in "$OUT"/*.o "$OUT"/*.err "$OUT"/MANIFEST.tmp; do
    [ -e "$f" ] && fail "build/contrib holds a working file: $(basename "$f")"
done

echo "  [PASS] $NAME: the vendored libsqlite3.a is in place before the veneer that needs it, and nothing is written in place"
