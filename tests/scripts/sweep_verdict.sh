#!/bin/sh
# The last step of `make test-ae`: passes only when the sweep wrote its tally,
# that tally has no failure, and every test the sweep listed reported.
#
#   sweep_verdict.sh <verdict-file> [<unreported-file>]
#
# The sweep is one long shell command. It writes the verdict file
# ("<passed> <failed> <skipped> <total> <listed>") right after it prints its
# "Aether Tests:" line, and exits 1 itself on a failure. A shell that stops
# before then, ended from outside or lost, can still leave make with status
# 0, and a sweep that printed no tally then read as a pass. This step runs in
# a shell of its own after that one, so it sees what the sweep left behind.
#
# <listed> is the number of tests the sweep handed its runners
# (tests/scripts/sweep_unreported.sh), and <total> the number that left a
# PASS, FAIL or SKIP marker. They differ when tests never reported: on a
# machine that stopped starting processes, most of a sweep's shell tests
# never ran and its xargs still returned 0 (#3111). The unreported file,
# when given, names them.
f="$1"
unrep="${2:-}"
if [ ! -s "$f" ]; then
    echo "test-ae: the sweep ended without its tally ($f was not written), so it did not pass" >&2
    exit 1
fi
read -r passed failed skipped total listed extra < "$f"
for n in "$passed" "$failed" "$skipped" "$total" "$listed"; do
    case "$n" in
        ''|*[!0-9]*)
            echo "test-ae: the sweep's tally is unreadable: '$(cat "$f")'" >&2
            exit 1 ;;
    esac
done
if [ -n "${extra:-}" ]; then
    echo "test-ae: the sweep's tally is unreadable: '$(cat "$f")'" >&2
    exit 1
fi
if [ "$failed" -ne 0 ] || [ "$total" -ne $((passed + failed + skipped)) ] || [ "$total" -eq 0 ]; then
    echo "test-ae: the sweep's tally is not a pass: $passed passed, $failed failed, $skipped skipped, $total total" >&2
    exit 1
fi
if [ "$total" -ne "$listed" ]; then
    echo "test-ae: $total of the $listed tests the sweep listed reported, so it did not pass" >&2
    if [ -n "$unrep" ] && [ -s "$unrep" ]; then
        echo "  never reported:" >&2
        sed 's/^/    /' "$unrep" >&2
    fi
    exit 1
fi
exit 0
