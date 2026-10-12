#!/bin/sh
# Keeps the lines of stdin that belong to shard k of n of the test sweep,
# AE_SWEEP_SHARD=k/n: the lines whose 0-based position modulo n is k-1, so
# the n shards of one sorted list cover it once between them. Without
# AE_SWEEP_SHARD every line passes.
#
# Why (#2757): the long CI legs (Windows MSYS2 x2, macOS x86_64) spend most
# of their 23 minutes in the sweep, on 4 cores. Each is split into two jobs
# that run in parallel: shard 1 runs `make ci` with AE_SWEEP_SHARD=1/2, and
# shard 2 runs `make ci-sweep` (the toolchain build and the sweep alone)
# with AE_SWEEP_SHARD=2/2.

shard="${AE_SWEEP_SHARD:-}"
[ -n "$shard" ] || exec cat

k=${shard%%/*}
n=${shard#*/}
case "$shard" in
    */*) ;;
    *) n="" ;;
esac
case "$k" in ''|*[!0-9]*) k="" ;; esac
case "$n" in ''|*[!0-9]*) n="" ;; esac
if [ -z "$k" ] || [ -z "$n" ] || [ "$n" -lt 1 ] || [ "$k" -lt 1 ] || [ "$k" -gt "$n" ]; then
    echo "sweep_shard.sh: AE_SWEEP_SHARD must be k/n with 1 <= k <= n, got '$shard'" >&2
    exit 2
fi
awk -v k="$k" -v n="$n" '(NR - 1) % n == k - 1'
