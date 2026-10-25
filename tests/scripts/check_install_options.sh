#!/bin/sh
# The installer's options, run by `make test-install`.
#
#   1. `install.sh --contrib-too <prefix>` installs the contrib archives into
#      <prefix>/lib/aether AND into the versions/<v> snapshot, so `ae use`
#      carries them; a plain install has neither (the negative control).
#   2. An unknown flag is refused before anything is installed, instead of
#      being taken as the install prefix.
#   3. `make install` as root with no PREFIX refuses (under sudo the default
#      ~/.aether would be root's); an explicit PREFIX is accepted.
#
# HOME is a scratch directory throughout, so a regression in the argument
# handling cannot install into the real ~/.aether. Only the libc-only
# host_aether bridge is built (MODULES=aether), to keep this quick.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$WORK/home"
export HOME="$WORK/home"
export AETHER_INSTALL_NO_RC=1

fail() { echo "  [FAIL] install options: $1"; exit 1; }
show_log() { tail -20 "$1" | sed 's/^/      /'; }

VER="$(tr -d '[:space:]' < VERSION)"
ARCHIVE="libaether_host_aether.a"

# --- 1. --contrib-too, and its control ---
echo "  install.sh --contrib-too..."
MODULES=aether ./install.sh --contrib-too "$WORK/with" < /dev/null > "$WORK/with.log" 2>&1 \
    || { show_log "$WORK/with.log"; fail "install.sh --contrib-too failed"; }
[ -f "$WORK/with/lib/aether/$ARCHIVE" ] \
    || { show_log "$WORK/with.log"; fail "--contrib-too did not install lib/aether/$ARCHIVE"; }
if [ -n "$VER" ] && [ "$VER" != "0.0.0-dev" ]; then
    [ -f "$WORK/with/versions/v$VER/lib/aether/$ARCHIVE" ] \
        || fail "--contrib-too installed $ARCHIVE but not into versions/v$VER, so 'ae use' drops it"
fi
grep -q "installed lib/aether/$ARCHIVE" "$WORK/with.log" \
    || fail "--contrib-too did not report the archives it installed"

echo "  install.sh without the flag..."
./install.sh "$WORK/without" < /dev/null > "$WORK/without.log" 2>&1 \
    || { show_log "$WORK/without.log"; fail "plain install.sh failed"; }
[ ! -f "$WORK/without/lib/aether/$ARCHIVE" ] \
    || fail "a plain install shipped $ARCHIVE; the check above proves nothing"

# --- 2. unknown flag ---
echo "  install.sh with an unknown flag..."
./install.sh --contrib-tooo < /dev/null > "$WORK/bogus.log" 2>&1
rc=$?
[ "$rc" -eq 2 ] || { show_log "$WORK/bogus.log"; fail "an unknown flag exited $rc, expected 2"; }
grep -q "unknown option '--contrib-tooo'" "$WORK/bogus.log" \
    || fail "an unknown flag was refused without naming it"
[ ! -e "$WORK/home/.aether" ] && [ ! -e "./--contrib-tooo" ] \
    || fail "an unknown flag still installed something"

# --- 3. make install as root ---
# A stand-in `id` that reports root: the guard asks `id -u`.
mkdir -p "$WORK/fakeroot"
printf '#!/bin/sh\n[ "$1" = "-u" ] && { echo 0; exit 0; }\nexec /usr/bin/id "$@"\n' > "$WORK/fakeroot/id"
chmod +x "$WORK/fakeroot/id"
MAKE_BIN="${MAKE:-make}"

echo "  make install as root, no PREFIX..."
PATH="$WORK/fakeroot:$PATH" "$MAKE_BIN" install > "$WORK/root.log" 2>&1 \
    && fail "make install as root with no PREFIX ran"
grep -q "sudo make install PREFIX=/usr/local" "$WORK/root.log" \
    || { show_log "$WORK/root.log"; fail "make install as root refused without saying what to type"; }
[ ! -e "$WORK/home/.aether" ] || fail "make install as root wrote to the default prefix before refusing"

echo "  make install as root, explicit PREFIX..."
PATH="$WORK/fakeroot:$PATH" "$MAKE_BIN" install PREFIX="$WORK/sys" > "$WORK/sys.log" 2>&1 \
    || { show_log "$WORK/sys.log"; fail "make install as root with an explicit PREFIX failed"; }
[ -x "$WORK/sys/bin/ae" ] || fail "make install PREFIX=... installed no bin/ae"

echo "  [PASS] install options: --contrib-too, unknown flags, root without PREFIX"
