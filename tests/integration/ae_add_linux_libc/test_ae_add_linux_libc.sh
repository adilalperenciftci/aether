#!/bin/sh
# #3073: glibc/musl release assets must have distinct identities on both CPUs.
# Probe the actual host selector under each platform's predefines, then fetch
# four differently marked, checksum-protected assets from a file:// forge.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae${EXE_EXT:-}"
COMPILER="${CC:-cc}"
[ -x "$AE" ] || { echo "[SKIP] ae_add_linux_libc: ae not built"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "[SKIP] ae_add_linux_libc: needs python3"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "[FAIL] ae_add_linux_libc: $1"; exit 1; }
native() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# System headers are processed before changing platform predefines: we test
# ae's selector, not the build host's system header internals or ABI.
cat > "$TMP/probe.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#ifdef TEST_LINUX
#undef __linux__
#undef __APPLE__
#undef _WIN32
#undef __FreeBSD__
#undef __ANDROID__
#undef __BIONIC__
#undef __UCLIBC__
#undef __GLIBC__
#undef __x86_64__
#undef __aarch64__
#define __linux__ 1
#ifdef TEST_GLIBC
#define __GLIBC__ 2
#endif
#ifdef TEST_ARM64
#define __aarch64__ 1
#else
#define __x86_64__ 1
#endif
#endif
#include "ae_release_platform.h"
int main(void) {
    const char* triple = ae_host_triple();
    puts(triple ? triple : "unsupported");
    return 0;
}
C
$COMPILER -I"$ROOT/tools" "$TMP/probe.c" -o "$TMP/native${EXE_EXT:-}"
HOST_TRIPLE="$("$TMP/native${EXE_EXT:-}")"
for arch in x86_64 arm64; do
    for libc in glibc musl; do
        flags="-DTEST_LINUX"
        [ "$arch" != arm64 ] || flags="$flags -DTEST_ARM64"
        suffix=""
        if [ "$libc" = glibc ]; then flags="$flags -DTEST_GLIBC"; else suffix="-musl"; fi
        $COMPILER -I"$ROOT/tools" $flags "$TMP/probe.c" -o "$TMP/probe${EXE_EXT:-}"
        got="$("$TMP/probe${EXE_EXT:-}")"
        [ "$got" = "linux-$arch$suffix" ] || fail "host selector: $arch/$libc returned $got"
    done
done

FORGE="$TMP/forge"
PKG="fake.host/user/libcpkg"
REL="$FORGE/$PKG/releases/download/v1.0.0"
mkdir -p "$REL"
printf '[package]\nname = "libcpkg"\nmodules = "."\nbinary = "libpkg"\n' > "$REL/aether.toml"
# Every payload is distinct and the published sidecar names the SAME target.
python3 - "$REL" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
for arch in ('x86_64', 'arm64'):
    for suffix in ('', '-musl'):
        triple = f'linux-{arch}{suffix}'
        asset = f'libpkg-v1.0.0-{triple}.so'
        payload = (triple + '\n').encode()
        (root / asset).write_bytes(payload)
        (root / (asset + '.sha256')).write_text(hashlib.sha256(payload).hexdigest() + '  ' + asset + '\n')
PY
FORGE_N="$(native "$FORGE")"
case "$FORGE_N" in /*) BASE="file://$FORGE_N" ;; *) BASE="file:///$FORGE_N" ;; esac
new_proj() {
    P="$TMP/project_$1"
    mkdir -p "$P/home"
    printf '[package]\nname = "consumer"\n\n[dependencies]\n' > "$P/aether.toml"
}
fetch() {
    (cd "$P" && HOME="$P/home" USERPROFILE="$(native "$P/home")" AE_RELEASE_BASE_URL="$BASE" \
        "$AE" add "$PKG@v1.0.0" "$@") > "$P/add.log" 2>&1
}
for triple in linux-x86_64 linux-x86_64-musl linux-arm64 linux-arm64-musl; do
    new_proj "$triple"
    fetch --target "$triple" || { cat "$P/add.log"; fail "fetch $triple"; }
    INST="$P/home/.aether/packages/$PKG/libpkg.so"
    cmp "$REL/libpkg-v1.0.0-$triple.so" "$INST" || fail "wrong bytes for $triple"
    grep -q 'Checksum verified' "$P/add.log" || fail "unverified $triple"
    # Later fetches must not replace the already fetched glibc or musl bytes.
    # Each consumer has its own cache, as on separate hosts/build jobs.
    for prev in "$TMP"/project_linux-*; do
        expected="${prev##*/project_}"
        cmp "$REL/libpkg-v1.0.0-$expected.so" "$prev/home/.aether/packages/$PKG/libpkg.so" \
            || fail "fetch $triple changed $expected"
    done
done
# Cache hits must honor --target too, without overwriting installed bytes.
P="$TMP/project_linux-x86_64"
fetch --target linux-x86_64 || fail 'same-target cache reuse failed'
if fetch --target linux-x86_64-musl; then fail 'glibc cache accepted for musl'; fi
grep -q 'has target linux-x86_64; requested linux-x86_64-musl' "$P/add.log" \
    || { cat "$P/add.log"; fail 'cache mismatch diagnostic'; }
cmp "$REL/libpkg-v1.0.0-linux-x86_64.so" "$P/home/.aether/packages/$PKG/libpkg.so" \
    || fail 'incompatible request overwrote cached glibc bytes'
# An old cache has no libc provenance, so it cannot safely satisfy a request.
rm "$P/home/.aether/packages/$PKG/.aether-binary-target"
if fetch --target linux-x86_64; then fail 'legacy cache accepted without target identity'; fi
grep -q 'unknown (legacy binary cache)' "$P/add.log" || fail 'legacy cache diagnostic'
printf 'linux-x86_64\n' > "$P/home/.aether/packages/$PKG/.aether-binary-target"

# --source clones may declare the binary release key too; they remain source
# caches and are reusable natively, but cannot satisfy a foreign binary fetch.
new_proj source_cache
mkdir -p "$P/home/.aether/packages/$PKG/.git"
cp "$REL/aether.toml" "$P/home/.aether/packages/$PKG/aether.toml"
fetch || fail 'source clone with a binary release key was treated as a binary cache'
if fetch --target linux-x86_64-musl; then fail 'source cache satisfied a foreign binary request'; fi
grep -q 'has target source' "$P/add.log" || fail 'source cache target diagnostic'

case "$HOST_TRIPLE" in
    linux-x86_64|linux-x86_64-musl|linux-arm64|linux-arm64-musl)
        new_proj automatic
        fetch || { cat "$P/add.log"; fail 'automatic host fetch'; }
        cmp "$REL/libpkg-v1.0.0-$HOST_TRIPLE.so" "$P/home/.aether/packages/$PKG/libpkg.so" \
            || fail 'automatic fetch selected the wrong libc'
        case "$HOST_TRIPLE" in
            *-musl) other="${HOST_TRIPLE%-musl}" ;;
            *) other="$HOST_TRIPLE-musl" ;;
        esac
        P="$TMP/project_$other"
        if fetch; then fail 'automatic selection reused the other libc from cache'; fi
        cmp "$REL/libpkg-v1.0.0-$other.so" "$P/home/.aether/packages/$PKG/libpkg.so" \
            || fail 'automatic selection changed foreign cached bytes'
        ;;
esac

# A missing asset or absent/bad checksum must not fetch the OTHER libc's
# payload sitting beside it. Exercise both CPUs in both directions.
for arch in x86_64 arm64; do
  for suffix in "" "-musl"; do
    triple="linux-$arch$suffix"
    asset="libpkg-v1.0.0-$triple.so"
    mv "$REL/$asset" "$TMP/saved-lib"
    new_proj "missing_$triple"
    if fetch --target "$triple"; then fail 'missing libc asset accepted'; fi
    grep -q "publishes no $asset" "$P/add.log" || { cat "$P/add.log"; fail 'missing-asset diagnostic'; }
    [ ! -d "$P/home/.aether/packages/$PKG" ] || fail 'failed fetch installed bytes'
    mv "$TMP/saved-lib" "$REL/$asset"

    mv "$REL/$asset.sha256" "$TMP/saved-sum"
    new_proj "nosum_$triple"
    if fetch --target "$triple"; then fail 'missing checksum accepted'; fi
    grep -q 'refusing to install an' "$P/add.log" || { cat "$P/add.log"; fail 'missing-checksum diagnostic'; }
    [ ! -d "$P/home/.aether/packages/$PKG" ] || fail 'unverified bytes installed'

    printf '%064d  %s\n' 0 "$asset" > "$REL/$asset.sha256"
    new_proj "badsum_$triple"
    if fetch --target "$triple"; then fail 'bad checksum accepted'; fi
    grep -q 'checksum MISMATCH' "$P/add.log" || { cat "$P/add.log"; fail 'checksum mismatch diagnostic'; }
    [ ! -d "$P/home/.aether/packages/$PKG" ] || fail 'corrupt bytes installed'
    mv "$TMP/saved-sum" "$REL/$asset.sha256"
  done
done
echo '[PASS] ae_add_linux_libc: both CPUs/libcs, automatic and explicit selection, distinct bytes, no libc fallback, required checksums'
