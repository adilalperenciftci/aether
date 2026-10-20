#!/bin/sh
# Runs lavapipe_d32s8_draw (aether#2410) `runs` times in each depth-stencil
# format, D32_SFLOAT_S8_UINT and then D24_UNORM_S8_UINT, on the Vulkan driver
# the environment selects, and reports how many runs crashed in each. The
# driver's crashes are reported, not judged: the step stays green while
# lavapipe has the bug and after it is fixed, and the counts say which. A
# crash is run again under gdb, when there is one, until it is caught, so the
# log carries the faulting instruction and the registers. A run that fails
# without crashing, or a device that is not lavapipe, is a broken setup and
# fails the step.
#
#   lavapipe_d32s8_report.sh <exe> [runs=20] [frames=10]
exe="$1"
runs="${2:-20}"
frames="${3:-10}"
shaders=contrib/vulkan/shaders
crashed=""
for fmt in d32s8 d24s8; do
    ok=0; crash=0; k=0; codes=""; unsupported=0
    while [ "$k" -lt "$runs" ]; do
        out="$("$exe" "$fmt" "$frames" "$shaders" 2>&1)"
        code=$?
        k=$((k + 1))
        [ "$k" -eq 1 ] && printf '%s\n' "$out" | head -1
        case "$out" in
            *llvmpipe*) ;;
            *) echo "$fmt: the device is not lavapipe, a broken setup:"; printf '%s\n' "$out"; exit 1 ;;
        esac
        if [ "$code" -eq 0 ]; then
            ok=$((ok + 1))
        elif [ "$code" -ge 128 ]; then
            crash=$((crash + 1)); codes="$codes $code"
        elif [ "$code" -eq 3 ]; then
            unsupported=1; break
        else
            echo "$fmt: run $k failed without crashing (exit $code), a broken setup:"
            printf '%s\n' "$out"
            exit 1
        fi
    done
    if [ "$unsupported" -eq 1 ]; then
        echo "$fmt: this lavapipe cannot use the format as a depth-stencil attachment"
        continue
    fi
    echo "$fmt: $runs runs of $frames frames, $crash crashed${codes:+ (exit codes:$codes)}, $ok drew every frame"
    [ "$crash" -gt 0 ] && crashed="$crashed $fmt"
done
[ -z "$crashed" ] && { echo "no crash in either format"; exit 0; }
echo "lavapipe crashed drawing into:$crashed (aether#2410); reported, not judged"
command -v gdb >/dev/null 2>&1 || exit 0
set -- $crashed
k=0
while [ "$k" -lt 6 ]; do
    k=$((k + 1))
    out="$(gdb -q -batch -ex run -ex bt -ex 'x/4i $pc' -ex 'info registers' \
               -ex 'thread apply all bt 8' --args "$exe" "$1" "$frames" "$shaders" 2>&1)"
    case "$out" in
        *"received signal"*)
            echo "gdb, $1, attempt $k:"
            printf '%s\n' "$out" | grep -v -e '^\[New Thread' -e '^\[Thread .* exited'
            exit 0 ;;
    esac
done
echo "gdb did not catch the crash in $k runs"
exit 0
