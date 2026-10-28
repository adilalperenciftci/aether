#!/bin/sh
# Every Aether program under benchmarks/ type-checks (#3295).
#
# Nothing else builds them: `make benchmark` runs only the cross-language
# suite, so the fork-join benchmarks stopped compiling when E0902 landed and
# nobody saw it. `ae check` is enough to keep them honest, and cheap: it
# stops before the C compiler.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"

if [ ! -x "$AE" ] && [ ! -x "$AE.exe" ]; then
    echo "  [SKIP] benchmarks_check: $AE not built"
    exit 0
fi

fail=0
count=0
for f in $(cd "$ROOT" && find benchmarks -name '*.ae' | sort); do
    case "$f" in
        */lib/*/module.ae) continue ;;   # a module, checked through its importers
    esac
    count=$((count + 1))
    dir="$(dirname "$ROOT/$f")"
    lib=""
    [ -d "$dir/lib" ] && lib="--lib $dir/lib"
    [ -d "$dir/../lib" ] && lib="--lib $dir/../lib"
    out="$(cd "$dir" && AETHER_HOME="$ROOT" "$AE" check $lib "$(basename "$f")" 2>&1)"
    if printf '%s\n' "$out" | grep -q '^error'; then
        echo "  [FAIL] benchmarks_check: $f does not type-check"
        printf '%s\n' "$out" | grep -E '^error|-->' | head -4 | sed 's/^/        /'
        fail=1
    fi
done

if [ "$fail" = 0 ]; then
    echo "  [PASS] benchmarks_check: $count benchmark programs type-check"
fi
exit $fail
