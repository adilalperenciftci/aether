#!/bin/sh
# x509-limbo (https://github.com/C2SP/x509-limbo) against
# std.cryptography.tls13_cert's path and name validation (#1298), in two
# parts: limbo's own cases, and the bettertls namespace (Netflix's bettertls
# name-constraint suite, which limbo imports and ships in the same file).
#
#   sh tests/conformance/x509_limbo/run.sh [limbo | bettertls | all]
#
# limbo.json (40 MB) is fetched at a pinned commit and checked against its
# SHA-256 into $CONFORMANCE_CACHE (default $HOME/.cache/aether-conformance),
# which the Linux CI job caches; it is never committed. To move the pin,
# change both values below and update expected.txt from a LIMBO_PRINT=1 run.
# limbo.ae and expected.txt say what each case checks and which do not agree.

set -e

LIMBO_COMMIT=1080e565f26e544bbe9cf99953be8a57c08e7e20
LIMBO_SHA256=611e337b9fb477b927bae65434650692cb9d2070ff5b05f975d0403510acd4de

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
CACHE="${CONFORMANCE_CACHE:-$HOME/.cache/aether-conformance}"
JSON="$CACHE/x509-limbo-$LIMBO_COMMIT.json"
WHAT="${1:-all}"

[ -x "$AE" ] || { echo "  [FAIL] x509-limbo: build/ae is not built"; exit 1; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

if [ ! -f "$JSON" ] || [ "$(sha256_of "$JSON")" != "$LIMBO_SHA256" ]; then
    mkdir -p "$CACHE"
    curl -fsSL --retry 3 -o "$JSON.part" \
        "https://raw.githubusercontent.com/C2SP/x509-limbo/$LIMBO_COMMIT/limbo.json" \
        || { rm -f "$JSON.part"; echo "  [FAIL] x509-limbo: could not fetch limbo.json"; exit 1; }
    got="$(sha256_of "$JSON.part")"
    if [ "$got" != "$LIMBO_SHA256" ]; then
        rm -f "$JSON.part"
        echo "  [FAIL] x509-limbo: limbo.json has SHA-256 $got, want $LIMBO_SHA256"
        exit 1
    fi
    mv "$JSON.part" "$JSON"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$AE" build "$SCRIPT_DIR/limbo.ae" -o "$TMP/limbo" >"$TMP/build.log" 2>&1 \
    || { sed -n '1,20p' "$TMP/build.log"; echo "  [FAIL] x509-limbo: limbo.ae did not build"; exit 1; }

# run <name> <id prefix> <id prefix to leave out>
run() {
    start=$(date +%s)
    if LIMBO_JSON="$JSON" LIMBO_EXPECTED="$SCRIPT_DIR/expected.txt" LIMBO_PREFIX="$2" LIMBO_EXCLUDE="$3" \
        "$TMP/limbo"; then
        echo "  [PASS] $1 ($(( $(date +%s) - start )) s)"
        return 0
    fi
    echo "  [FAIL] $1"
    return 1
}

rc=0
case "$WHAT" in
    limbo | all) run x509-limbo "" "bettertls::" || rc=1 ;;
esac
case "$WHAT" in
    bettertls | all) run bettertls "bettertls::" "" || rc=1 ;;
esac
exit $rc
