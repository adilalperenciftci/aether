#!/bin/sh
# The last step of `make test-ae`: passes only when the sweep wrote its tally
# and that tally has no failure.
#
#   sweep_verdict.sh <verdict-file>
#
# The sweep is one long shell command. It writes the verdict file
# ("<passed> <failed> <skipped> <total>") right after it prints its
# "Aether Tests:" line, and exits 1 itself on a failure. A shell that stops
# before then, ended from outside or lost, can still leave make with status
# 0, and a sweep that printed no tally then read as a pass. This step runs in
# a shell of its own after that one, so it sees what the sweep left behind.
f="$1"
if [ ! -s "$f" ]; then
    echo "test-ae: the sweep ended without its tally ($f was not written), so it did not pass" >&2
    exit 1
fi
read -r passed failed skipped total < "$f"
case "$passed$failed$skipped$total" in
    ''|*[!0-9]*)
        echo "test-ae: the sweep's tally is unreadable: '$(cat "$f")'" >&2
        exit 1 ;;
esac
if [ "$failed" -ne 0 ] || [ "$total" -ne $((passed + failed + skipped)) ] || [ "$total" -eq 0 ]; then
    echo "test-ae: the sweep's tally is not a pass: $passed passed, $failed failed, $skipped skipped, $total total" >&2
    exit 1
fi
exit 0
