#!/bin/sh
# A program that panics and catches links the panic machinery from the
# runtime and nothing that only a sandbox or a library call needs.
#
# #2955 made a panic end the sandbox levels pushed inside the frame it
# leaves, by a direct call into aether_sandbox.c: every program with a panic
# then linked the sandbox and the audit log it writes to (17 KB more for
# this fixture on Windows MinGW). #2956 made a `try` ask, when it
# catches, whether an interruption of a library call is on its way, by a
# call into aether_exec.c: every program with a `try` would have linked the
# execution frames, the caller info and the sandbox. The panic now reaches
# the sandbox through a pointer the sandbox sets before any level can
# exist, and the two calls a `try` makes live with the panic frames.
#
# Fixture, not a test: catches.ae is built by this driver.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
export AETHER_HOME="$ROOT"

[ -x "$AE" ] || { echo "  [SKIP] panic_link_surface: $AE not built"; exit 0; }
command -v nm >/dev/null 2>&1 || { echo "  [SKIP] panic_link_surface: no nm"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" || true' EXIT

if ! "$AE" build "$SCRIPT_DIR/catches.ae" -o "$TMP/catches" > "$TMP/build.log" 2>&1; then
    echo "  [FAIL] panic_link_surface: ae build failed"
    tail -5 "$TMP/build.log" | sed 's/^/        /'
    exit 1
fi
exe="$TMP/catches"
[ -f "$TMP/catches.exe" ] && exe="$TMP/catches.exe"

got=$("$exe" 2>&1)
want='2
caught: too big'
if [ "$got" != "$want" ]; then
    echo "  [FAIL] panic_link_surface: the program printed"
    printf '%s\n' "$got" | sed 's/^/        /'
    exit 1
fi

nm "$exe" > "$TMP/syms" 2>/dev/null
has() { grep -Eq "[ _]$1\$" "$TMP/syms"; }

# The symbol table is there to read: the panic frames are linked.
if ! has aether_try_push; then
    echo "  [SKIP] panic_link_surface: no symbol table to read in $exe"
    exit 0
fi

rc=0
# One function of each object that must stay out, with what pulled it in.
for pair in aether_sandbox_push:aether_sandbox.o aether_sandbox_audit:aether_audit.o \
            aether_exec_enter:aether_exec.o aether_caller_leave:aether_host.o; do
    sym=${pair%%:*}
    obj=${pair#*:}
    if has "$sym"; then
        echo "  [FAIL] panic_link_surface: the program links $obj ($sym)"
        rc=1
    fi
done
[ $rc -eq 0 ] && echo "  [PASS] panic_link_surface: panic and try link no sandbox, audit or execution frames"
exit $rc
