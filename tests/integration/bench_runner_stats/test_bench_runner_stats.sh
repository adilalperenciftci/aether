#!/bin/sh
# The cross-language benchmark runner's statistics and output parsing
# (benchmarks/cross-language/lib/benchstats): the median is the middle of the
# sorted runs, not the middle run (#3076); the coefficient of variation is
# the sample standard deviation over the mean, never negative; CPU time and
# peak memory are read from GNU and BSD time; a missing number is -1, not 0;
# and the checksums and unit counts a correct run prints. The runner itself
# must type-check, since nothing else compiles it outside `make benchmark`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -n "${EXE_EXT:-}" ] && AE="$AE$EXE_EXT"

[ -x "$AE" ] || [ -x "$AE.exe" ] || { echo "  [SKIP] bench_runner_stats: ae not built"; exit 0; }

BENCH="$ROOT/benchmarks/cross-language"
out="$(cd "$BENCH" && AETHER_HOME="$ROOT" "$AE" run test_benchstats.ae 2>&1)"
if [ "$(printf '%s\n' "$out" | tail -n 1)" != "ok" ]; then
    echo "  [FAIL] bench_runner_stats: test_benchstats.ae"
    printf '%s\n' "$out" | sed 's/^/        /' | tail -n 20
    exit 1
fi

chk="$(cd "$BENCH" && AETHER_HOME="$ROOT" "$AE" check run_benchmarks.ae 2>&1)"
if [ $? -ne 0 ]; then
    echo "  [FAIL] bench_runner_stats: run_benchmarks.ae does not type-check"
    printf '%s\n' "$chk" | sed 's/^/        /' | head -n 20
    exit 1
fi

echo "  [PASS] bench_runner_stats: median, spread, time parsing and checksums; the runner type-checks"
