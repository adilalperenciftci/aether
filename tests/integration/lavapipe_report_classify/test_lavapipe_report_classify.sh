#!/bin/sh
# .github/scripts/lavapipe_d32s8_report.sh (#2410) judges each run of the
# D32S8 draw by what it printed, not by its exit code alone: MSYS2's sh
# reports a Windows access violation as 139, but heap corruption as 127 and
# abort() as 3, the program's own code for a format it cannot use. Read by
# exit code, a 127 failed the CI step as "a broken setup" and an abort was
# taken for an unsupported format, hiding the crash.
#
# A stand-in for the draw program prints a device line (or none) and exits
# with a given code; each case checks the report's verdict and exit. No GPU.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REPORT="$ROOT/.github/scripts/lavapipe_d32s8_report.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# The stand-in: STANDIN_DEVICE names the device line's device (none when
# empty), STANDIN_LINE is printed after it, STANDIN_CODE is the exit code.
cat > "$TMP/standin" <<'SH'
#!/bin/sh
[ -n "$STANDIN_DEVICE" ] && echo "device: $STANDIN_DEVICE, driver version 0x1, depth format $1, $2 frames"
[ -n "$STANDIN_LINE" ] && echo "$STANDIN_LINE"
exit "$STANDIN_CODE"
SH
chmod +x "$TMP/standin"

# case <name> <want exit> <text> DEVICE LINE CODE: the report on 2 runs of
# each format prints <text> and exits <want exit>.
case_() {
    name="$1"; want="$2"; text="$3"
    out=$(cd "$TMP" && STANDIN_DEVICE="$4" STANDIN_LINE="$5" STANDIN_CODE="$6" \
          PATH="/usr/bin:/bin" sh "$REPORT" ./standin 2 1 2>&1)
    rc=$?
    case "$out" in
        *"$text"*) ;;
        *) echo "  [FAIL] $name: no \"$text\""; echo "$out" | sed 's/^/        /'
           fails=$((fails + 1)); return ;;
    esac
    if [ "$rc" -ne "$want" ]; then
        echo "  [FAIL] $name: exit $rc, want $want"; echo "$out" | sed 's/^/        /'
        fails=$((fails + 1))
    fi
}

LP="llvmpipe (LLVM 20.1.8, 256 bits)"
case_ drew          0 "no crash in either format"                                "$LP" "" 0
case_ segv          0 "2 crashed (exit codes: 139 139)"                          "$LP" "" 139
case_ heap          0 "2 crashed (exit codes: 127 127)"                          "$LP" "" 127
case_ before_device 0 "2 crashed (exit codes: 127 127)"                          ""    "" 127
case_ abort         0 "2 crashed (exit codes: 3 3)"                              "$LP" "" 3
case_ unsupported   0 "d32s8: this lavapipe cannot use the format"               "$LP" \
    "the device has no optimal-tiling depth-stencil attachment in this format" 3
case_ setup         1 "d32s8: run 1 failed without crashing (exit 2), a broken setup" \
    "$LP" "FAILED vkCreateDevice(...) = -3 (line 140)" 2
case_ no_device     1 "a broken setup"                                           ""    "no device" 2
case_ other_device  1 "d32s8: the device is not lavapipe, a broken setup"        "NVIDIA RTX" "" 0

if [ "$fails" -ne 0 ]; then exit 1; fi
echo "  [PASS] lavapipe_report_classify: crashes counted by any failing exit, unsupported and broken setups only by what the run printed"
