#!/bin/sh
# #1362: a package is identified by the hash of its tree, not by where it
# came from. `ae add` pins the hash in aether.toml's [dependency-hashes]; a
# later add (a fresh machine, an emptied cache) must get the same tree, a
# build refuses an installed package that is not it, and --update is the one
# way to move a pin. #3304: a package name with `..` is refused before
# anything is written.
#
# Hermetic: a file:// mirror through AE_RELEASE_BASE_URL, laid out as
# <mirror>/<pkg>/archive/<ref>.tar.gz. HOME is a scratch directory.
#
# Pinned properties:
#   1. an add with no version installs the version aether.toml names, and
#      checks it against the pinned hash,
#   2. an archive that changed since it was pinned (a moved tag) is refused:
#      exit 1, nothing in the cache, the manifest untouched,
#   3. --update takes the new tree and pins its hash,
#   4. another version needs --update, which moves the version, the hash and
#      the installed tree,
#   5. a build stops when the installed tree is not the pinned one,
#   6. the cache holds one version of a package: another project's request
#      for another version is refused, not served the wrong tree,
#   7. without a version the default branch is installed and pinned,
#   8. editing the manifest keeps every other line and section in place,
#   9. `..` in a package name is refused, and nothing is written (#3304); so
#      is a version that is not a tag name, typed or read from aether.toml.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"
[ -x "$AE" ] || { echo "  [SKIP] ae_add_hash_pin: ae not built"; exit 0; }
command -v tar >/dev/null 2>&1 || { echo "  [SKIP] ae_add_hash_pin: tar needed to build the fixture"; exit 0; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() {
    echo "  [FAIL] ae_add_hash_pin: $1"
    [ -n "$2" ] && [ -f "$2" ] && sed 's/^/    /' "$2" | head -24
    exit 1
}

PKG="example.com/acme/widget"
ARCH="$TMP/mirror/$PKG/archive"
mkdir -p "$ARCH"
# archive <ref> <content of f.txt>
archive() {
    rm -rf "$TMP/src"
    mkdir -p "$TMP/src/widget-$1"
    printf '%s\n' "$2" > "$TMP/src/widget-$1/f.txt"
    printf '[package]\nname = "widget"\nmodules = "."\n' > "$TMP/src/widget-$1/aether.toml"
    ( cd "$TMP/src" && tar -czf "$ARCH/$1.tar.gz" "widget-$1" ) || fail "could not build the archive for $1"
}
archive v0.2.0 two
archive v0.2.1 three
archive HEAD head

export HOME="$TMP/home"
if command -v cygpath >/dev/null 2>&1; then
    USERPROFILE="$(cygpath -m "$TMP/home")"
    export AE_RELEASE_BASE_URL="file://$(cygpath -m "$TMP/mirror")"
else
    USERPROFILE="$TMP/home"
    export AE_RELEASE_BASE_URL="file://$TMP/mirror"
fi
export USERPROFILE
mkdir -p "$HOME"
CACHE="$HOME/.aether/packages/$PKG"

# The manifest has a comment, a section after [dependencies] and an entry
# in it, so the edits must place lines, not append them.
P="$TMP/proj"
mkdir -p "$P"
cat > "$P/aether.toml" <<'EOF'
[package]
name = "consumer"
version = "0.1.0"

# what this project uses
[dependencies]
"example.com/acme/other" = "1.0.0"

[build]
defines = "FAST"
EOF
cp "$P/aether.toml" "$TMP/manifest.orig"

# Byte for byte (cksum: coreutils, where cmp and diff may be absent).
same_file() { [ "$(cksum < "$1")" = "$(cksum < "$2")" ]; }

hash_of() { sed -n "s|^\"$PKG\" = \"\(sha256-[0-9a-f]*\)\"|\1|p" "$P/aether.toml" | tail -1; }

( cd "$P" && "$AE" add "$PKG@v0.2.1" ) > "$TMP/first.log" 2>&1 || fail "the first add failed" "$TMP/first.log"
PIN="$(hash_of)"
[ -n "$PIN" ] || fail "no hash pinned" "$P/aether.toml"

# --- 8. the edits keep every other line ---------------------------------
for line in '# what this project uses' '"example.com/acme/other" = "1.0.0"' 'defines = "FAST"'; do
    grep -qxF "$line" "$P/aether.toml" || fail "the edit lost '$line'" "$P/aether.toml"
done
deps_line=$(grep -n "^\"$PKG\" = \"v0.2.1\"" "$P/aether.toml" | cut -d: -f1)
build_line=$(grep -n '^\[build\]' "$P/aether.toml" | cut -d: -f1)
[ -n "$deps_line" ] && [ "$deps_line" -lt "$build_line" ] \
    || fail "the dependency was not added inside [dependencies]" "$P/aether.toml"

# --- 1. a fresh machine: no version given, the manifest's is installed ---
rm -rf "$CACHE" "$CACHE.fetched"
( cd "$P" && "$AE" add "$PKG" ) > "$TMP/fresh.log" 2>&1 || fail "the fresh-machine add failed" "$TMP/fresh.log"
[ "$(cat "$CACHE/f.txt")" = "three" ] || fail "the fresh-machine add did not install v0.2.1" "$TMP/fresh.log"
[ "$(hash_of)" = "$PIN" ] || fail "the fresh-machine add changed the pin" "$P/aether.toml"
grep -q "\"$PKG\" = \"v0.2.1\"" "$P/aether.toml" || fail "the version changed" "$P/aether.toml"

# --- 5. a build stops on an installed tree that is not the pinned one ----
( cd "$P" && "$AE" lib-path ) > "$TMP/lp_ok.log" 2>&1 || fail "lib-path failed on the pinned tree" "$TMP/lp_ok.log"
cp "$CACHE.fetched" "$TMP/record.keep"
sed 's/^hash .*/hash sha256-0000000000000000000000000000000000000000000000000000000000000000/' \
    "$TMP/record.keep" > "$CACHE.fetched"
( cd "$P" && "$AE" lib-path ) > "$TMP/lp_bad.log" 2>&1 && fail "lib-path accepted another tree than the pinned one" "$TMP/lp_bad.log"
grep -q "installed as another tree" "$TMP/lp_bad.log" || fail "no diagnostic for the wrong tree" "$TMP/lp_bad.log"
cp "$TMP/record.keep" "$CACHE.fetched"

# --- 2. a moved tag is refused -------------------------------------------
archive v0.2.1 three-moved
rm -rf "$CACHE" "$CACHE.fetched"
cp "$P/aether.toml" "$TMP/manifest.before"
( cd "$P" && "$AE" add "$PKG" ) > "$TMP/moved.log" 2>&1 && fail "a moved tag was accepted" "$TMP/moved.log"
grep -q "is not the tree aether.toml pins" "$TMP/moved.log" || fail "no diagnostic for a moved tag" "$TMP/moved.log"
[ ! -e "$CACHE" ] && [ ! -e "$CACHE.fetched" ] || fail "a refused tree was left in the cache" "$TMP/moved.log"
same_file "$P/aether.toml" "$TMP/manifest.before" || fail "a refused add changed aether.toml" "$P/aether.toml"

# --- 3. --update takes it ------------------------------------------------
( cd "$P" && "$AE" add "$PKG" --update ) > "$TMP/upd.log" 2>&1 || fail "--update failed" "$TMP/upd.log"
[ "$(cat "$CACHE/f.txt")" = "three-moved" ] || fail "--update did not install the new tree" "$TMP/upd.log"
NEWPIN="$(hash_of)"
[ -n "$NEWPIN" ] && [ "$NEWPIN" != "$PIN" ] || fail "--update did not pin the new hash" "$P/aether.toml"
[ "$(grep -c "^\"$PKG\" = " "$P/aether.toml")" = 2 ] || fail "--update duplicated a line" "$P/aether.toml"

# --- 4. another version needs --update -----------------------------------
( cd "$P" && "$AE" add "$PKG@v0.2.0" ) > "$TMP/other.log" 2>&1 && fail "another version was taken without --update" "$TMP/other.log"
grep -q -- "--update" "$TMP/other.log" || fail "the refusal does not say how to move the pin" "$TMP/other.log"
( cd "$P" && "$AE" add "$PKG@v0.2.0" --update ) > "$TMP/move.log" 2>&1 || fail "@v0.2.0 --update failed" "$TMP/move.log"
[ "$(cat "$CACHE/f.txt")" = "two" ] || fail "--update did not replace the installed tree" "$TMP/move.log"
grep -q "\"$PKG\" = \"v0.2.0\"" "$P/aether.toml" || fail "--update did not move the version" "$P/aether.toml"
[ "$(hash_of)" != "$NEWPIN" ] || fail "--update did not move the hash" "$P/aether.toml"
[ ! -e "$CACHE.new" ] || fail "--update left its staging tree" "$TMP/move.log"

# --- 6. one version per package in the cache -----------------------------
Q="$TMP/other_project"
mkdir -p "$Q"
printf '[package]\nname = "q"\n' > "$Q/aether.toml"
( cd "$Q" && "$AE" add "$PKG@v0.2.1" ) > "$TMP/shared.log" 2>&1 && fail "the cache served v0.2.0 for a v0.2.1 request" "$TMP/shared.log"
grep -q "is installed at v0.2.0" "$TMP/shared.log" || fail "no diagnostic for the shared cache" "$TMP/shared.log"
[ "$(cat "$CACHE/f.txt")" = "two" ] || fail "a refused add changed the installed tree" "$TMP/shared.log"

# --- 7. the default branch -----------------------------------------------
rm -rf "$CACHE" "$CACHE.fetched"
( cd "$Q" && "$AE" add "$PKG" ) > "$TMP/head.log" 2>&1 || fail "an unversioned add failed" "$TMP/head.log"
[ "$(cat "$CACHE/f.txt")" = "head" ] || fail "an unversioned add did not install the default branch" "$TMP/head.log"
grep -q "\"$PKG\" = \"latest\"" "$Q/aether.toml" || fail "an unversioned add did not record latest" "$Q/aether.toml"
grep -q "\"$PKG\" = \"sha256-" "$Q/aether.toml" || fail "an unversioned add did not pin its hash" "$Q/aether.toml"

# --- 9. `..` is refused (#3304) ------------------------------------------
cp "$Q/aether.toml" "$TMP/q.before"
( cd "$Q" && "$AE" add "example.com/../../escape" ) > "$TMP/dots.log" 2>&1 && fail "a package path with .. was accepted" "$TMP/dots.log"
[ ! -e "$HOME/.aether/escape" ] && [ ! -e "$HOME/escape" ] || fail "a package path with .. wrote outside the cache" "$TMP/dots.log"
same_file "$Q/aether.toml" "$TMP/q.before" || fail "a refused package path changed aether.toml" "$Q/aether.toml"
# So is a version that is not a tag name, typed or read from the manifest:
# it would go into the archive's URL.
( cd "$Q" && "$AE" add "$PKG@v1?x=1" ) > "$TMP/badver.log" 2>&1 && fail "a version with ? was accepted" "$TMP/badver.log"
R="$TMP/odd_manifest"
mkdir -p "$R"
printf '[package]\nname = "r"\n\n[dependencies]\n"%s" = "^1.0#frag"\n' "$PKG" > "$R/aether.toml"
rm -rf "$CACHE" "$CACHE.fetched"
( cd "$R" && "$AE" add "$PKG" ) > "$TMP/oddver.log" 2>&1 && fail "a manifest version with ^ and # was fetched" "$TMP/oddver.log"
grep -q "not a version" "$TMP/oddver.log" || fail "no diagnostic for the manifest's version" "$TMP/oddver.log"
[ ! -e "$CACHE" ] || fail "a refused version installed a tree" "$TMP/oddver.log"

echo "  [PASS] ae_add_hash_pin: the tree's hash is pinned, checked on add and build, moved only by --update; .. and non-versions refused"
