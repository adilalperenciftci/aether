#!/bin/sh
# Re-vendor PCRE2 into std/regex/pcre2/ (#1389).
#
# Downloads the pinned upstream release, verifies its checksum, and copies
# the byte-identical subset that std/regex/aether_pcre2_vendored.c compiles.
# Run from the repo root. To bump the version: update VERSION and SHA256
# below (sha from the pcre2 GitHub release page), run the script, review
# the diff, and update THIRD_PARTY_LICENSES.md if the licence text changed.
# The release is also GPG-signed (pcre2-<v>.tar.gz.sig); upstream's
# SECURITY.md names the signing key. Check it by hand when bumping:
#   gpg --recv-keys A95536204A3BB489715231282A98E77EB6F24CA8
#   gpg --verify pcre2-<v>.tar.gz.sig pcre2-<v>.tar.gz
# When the source list in NON-AUTOTOOLS-BUILD changes, update the lists
# below and the #includes in aether_pcre2_vendored.c together;
# `gcc -MM std/regex/aether_pcre2_vendored.c -DAETHER_VENDOR_PCRE2` lists
# every file the unity build reads.
#
# The vendored tree is VERBATIM upstream — no local patches, ever. The three
# files whose committed name differs from their upstream name are the ones
# upstream itself designates for non-autotools embedding (see
# NON-AUTOTOOLS-BUILD in the tarball):
#   src/pcre2.h.generic          -> pcre2.h
#   src/config.h.generic         -> config.h
#   src/pcre2_chartables.c.dist  -> pcre2_chartables.c
# Feature selection (PCRE2_CODE_UNIT_WIDTH=8, SUPPORT_UNICODE, JIT off) is
# done by command-line-equivalent #defines in aether_pcre2_vendored.c, not
# by editing config.h, so the whole tree stays checkable against upstream.
set -eu

VERSION=10.49
SHA256=929f0b20e62879252a15886b06c89f1edef61a363cbd5826fb041080a5e557ae
URL="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${VERSION}/pcre2-${VERSION}.tar.gz"
DEST=std/regex/pcre2

[ -f Makefile ] && [ -d std/regex ] || { echo "run from the repo root" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "fetching pcre2-${VERSION}..."
curl -sL -o "$TMP/pcre2.tar.gz" "$URL"
echo "${SHA256}  $TMP/pcre2.tar.gz" | sha256sum -c - >/dev/null \
    || { echo "SHA-256 mismatch — refusing to vendor" >&2; exit 1; }
tar -xzf "$TMP/pcre2.tar.gz" -C "$TMP"
SRC="$TMP/pcre2-${VERSION}/src"

rm -rf "$DEST"
mkdir -p "$DEST"

# The 31 sources NON-AUTOTOOLS-BUILD lists, which aether_pcre2_vendored.c
# #includes.
for f in \
    pcre2_auto_possess pcre2_chkdint pcre2_compile pcre2_compile_cgroup \
    pcre2_compile_class pcre2_config pcre2_context pcre2_convert \
    pcre2_dfa_match pcre2_error pcre2_extuni pcre2_find_bracket \
    pcre2_jit_compile pcre2_maketables pcre2_match pcre2_match_data \
    pcre2_match_next pcre2_newline pcre2_ord2utf pcre2_pattern_info \
    pcre2_script_run pcre2_serialize pcre2_string_utils pcre2_study \
    pcre2_substitute pcre2_substring pcre2_tables pcre2_ucd \
    pcre2_valid_utf pcre2_xclass; do
    cp "$SRC/$f.c" "$DEST/"
done

# Internal headers the sources include, and the *_inc.h files they include
# textually (never compiled standalone).
for h in pcre2_internal.h pcre2_intmodedep.h pcre2_ucp.h pcre2_compile.h \
    pcre2_util.h pcre2_jit_match_inc.h pcre2_jit_misc_inc.h \
    pcre2_ucptables_inc.h; do
    cp "$SRC/$h" "$DEST/"
done

# The upstream-designated renames for non-autotools embedding.
cp "$SRC/pcre2.h.generic"         "$DEST/pcre2.h"
cp "$SRC/config.h.generic"        "$DEST/config.h"
cp "$SRC/pcre2_chartables.c.dist" "$DEST/pcre2_chartables.c"

# Upstream licence, kept beside the code it covers (also reproduced in
# THIRD_PARTY_LICENSES.md).
cp "$TMP/pcre2-${VERSION}/LICENCE.md" "$DEST/LICENCE.md"

cat > "$DEST/VENDOR.md" <<EOF
# Vendored PCRE2 ${VERSION}

Byte-identical subset of upstream PCRE2 ${VERSION}
(<https://github.com/PCRE2Project/pcre2>), BSD-3-Clause — full licence in
\`LICENCE.md\` here and in \`THIRD_PARTY_LICENSES.md\`. Vendored for #1389 so
\`std.regex\` works without a system libpcre2-8: native builds on boxes
without the library, and \`ae build --target ...\` cross builds with no
CROSSBUILD_SYSROOT.

- Upstream tarball: pcre2-${VERSION}.tar.gz
- SHA-256: \`${SHA256}\`
- Regenerate with: \`scripts/vendor-pcre2.sh\` (edit VERSION/SHA256 there to bump)

Three files are upstream files under the name upstream designates for
non-autotools embedding: \`pcre2.h\` (from \`pcre2.h.generic\`), \`config.h\`
(from \`config.h.generic\`), \`pcre2_chartables.c\` (from
\`pcre2_chartables.c.dist\`). Everything else keeps its upstream name.

**No local patches.** Feature selection lives in
\`std/regex/aether_pcre2_vendored.c\` (8-bit code units, Unicode on, JIT
off); nothing in this directory is edited. If a change is ever needed,
it goes upstream — not here.

This directory is compiled ONLY as textual includes of
\`aether_pcre2_vendored.c\` (a single translation unit, guarded by
\`AETHER_VENDOR_PCRE2\`). Its .c files must never be added to MANIFEST,
STD_SRC, or any build's source list.
EOF

echo "vendored pcre2-${VERSION} into $DEST:"
ls "$DEST" | wc -l
echo "done — review with: git status $DEST"
