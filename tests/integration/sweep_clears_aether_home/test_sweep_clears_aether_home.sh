#!/bin/sh
# Issue #3342: the sweep's runners drop an inherited AETHER_HOME. With it set
# to an install (as install.sh sets it), a test that ran the tree's aetherc
# without pinning it compiled against the installed std, and failed on the
# install's sources where the two differed. The tree is what the sweep tests,
# so neither runner passes the developer's AETHER_HOME on; a test that wants
# an install names one itself.
#
# Each runner is run here as the sweep runs it, with AETHER_HOME set, on a
# probe that fails if it can see the variable: a shell test
# (run_ae_sh_dir.sh) and an .ae test (run_ae_test.sh).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
NAME=sweep_clears_aether_home

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] $NAME: ae not built"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rm -f "$ROOT"/build/test_*sweep_home_probe*' EXIT

mkdir -p "$TMP/sh" "$TMP/ae" "$TMP/marks_sh" "$TMP/marks_ae"
cat > "$TMP/sh/test_sweep_home_probe.sh" <<'PROBE'
#!/bin/sh
if [ -n "${AETHER_HOME+x}" ]; then
    echo "  [FAIL] the test sees AETHER_HOME=$AETHER_HOME"
    exit 1
fi
echo "  [PASS] no AETHER_HOME"
PROBE
cat > "$TMP/ae/test_sweep_home_probe.ae" <<'PROBE'
import std.os

extern exit(code: int)

main() {
    home = os.getenv("AETHER_HOME")
    if home != "" {
        println("FAIL: the test sees AETHER_HOME=${home}")
        exit(1)
    }
    println("OK")
}
PROBE

fails=0
AETHER_HOME="$TMP/an-install" sh "$ROOT/tests/scripts/run_ae_sh_dir.sh" \
    "$TMP/sh" "$TMP/marks_sh" "$ROOT" >"$TMP/sh.log" 2>&1
if ! ls "$TMP/marks_sh"/PASS_* >/dev/null 2>&1; then
    echo "  [FAIL] $NAME: run_ae_sh_dir.sh passed AETHER_HOME on to a shell test"
    sed 's/^/        /' "$TMP/sh.log" | head -12
    fails=$((fails + 1))
fi
AETHER_HOME="$TMP/an-install" sh "$ROOT/tests/scripts/run_ae_test.sh" \
    "$TMP/ae/test_sweep_home_probe.ae" "$TMP/marks_ae" "$ROOT" >"$TMP/ae.log" 2>&1
if ! ls "$TMP/marks_ae"/PASS_* >/dev/null 2>&1; then
    echo "  [FAIL] $NAME: run_ae_test.sh passed AETHER_HOME on to an .ae test"
    sed 's/^/        /' "$TMP/ae.log" | head -12
    fails=$((fails + 1))
fi
[ "$fails" -eq 0 ] || exit 1
echo "  [PASS] $NAME: neither sweep runner passes an inherited AETHER_HOME on"
exit 0
