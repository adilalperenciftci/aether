#!/bin/sh
# Keeps the lines of stdin that belong to shard k of n of the test sweep,
# AE_SWEEP_SHARD=k/n: the lines whose 0-based position modulo n is k-1, so
# the n shards of one sorted list cover it once between them. k can be a
# comma-separated list (AE_SWEEP_SHARD=2,3/3 keeps shards 2 and 3). Without
# AE_SWEEP_SHARD every line passes.
#
# Why (#2757): the long CI legs (Windows MSYS2 x2, macOS x86_64) spend most
# of their 23 minutes in the sweep, on 4 cores. Each is split into two jobs
# that run in parallel. On Windows one runs `make ci` with AE_SWEEP_SHARD=1/3
# and the other `make ci-sweep` (the toolchain build and the sweep alone)
# with AE_SWEEP_SHARD=2,3/3: the first also runs every stage of `make ci`
# around the sweep, about 5 minutes more on those runners, so it takes the
# smaller share and the two finish together; an even split left it 5 minutes
# behind the other. On macOS x86_64 both run `make ci-sweep`, with 1/2 and
# 2/2, since the ARM64 leg runs the rest of `make ci` on macOS (#2772).

shard="${AE_SWEEP_SHARD:-}"
[ -n "$shard" ] || exec cat

usage() {
    echo "sweep_shard.sh: AE_SWEEP_SHARD must be k/n or k,k.../n with 1 <= k <= n, got '$shard'" >&2
    exit 2
}

case "$shard" in
    */*) ;;
    *) usage ;;
esac
ks=${shard%/*}
n=${shard##*/}
case "$n" in ''|*[!0-9]*) usage ;; esac
[ "$n" -ge 1 ] || usage
case "$ks" in ''|,*|*,|*,,*|*[!0-9,]*) usage ;; esac
for k in $(printf '%s\n' "$ks" | tr ',' ' '); do
    [ "$k" -ge 1 ] && [ "$k" -le "$n" ] || usage
done
awk -v ks="$ks" -v n="$n" '
    BEGIN { m = split(ks, list, ","); for (i = 1; i <= m; i++) keep[list[i] - 1] = 1 }
    ((NR - 1) % n) in keep
'
