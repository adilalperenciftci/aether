#!/bin/sh
# The tests `make test-ae` listed that never reported (#3111).
#
#   sweep_unreported.sh <tmpdir> <out>
#
# The sweep writes the units it hands its two xargs to <tmpdir>/units_ae.txt
# (one .ae path each) and <tmpdir>/units_sh.txt (a test_*.sh path, or a
# directory whose test_*.sh files run one after another), and each test that
# runs leaves a PASS_, FAIL_ or SKIP_ marker under the name sweep_name.sh
# gives it. This writes to <out> the name of every listed test with no
# marker, one per line, sorted, and prints the number of tests listed.
#
# Why: when a Windows machine stopped starting processes in the middle of a
# local sweep, most of the shell tests never ran, and the sweep's xargs still
# returned 0. The sweep counted the markers it had, and its total said
# nothing of the tests that never ran. A total checked against this count
# does.
#
# A handful of processes whatever the size of the lists: one find over all
# the directories, one sed for every name, and one listing of the markers.
set -u

tmpdir="$1"
out="$2"
. "$(dirname "$0")/sweep_name.sh"

ae_units="$tmpdir/units_ae.txt"
sh_units="$tmpdir/units_sh.txt"
[ -f "$ae_units" ] || : > "$ae_units"
[ -f "$sh_units" ] || : > "$sh_units"

# A unit that is a file is one test; a directory is each test_*.sh directly
# in it, as run_ae_sh_dir.sh runs them.
dirs=$(while IFS= read -r u; do [ -d "$u" ] && printf '%s\n' "$u"; done < "$sh_units")
{
    cat "$ae_units"
    while IFS= read -r u; do [ -f "$u" ] && printf '%s\n' "$u"; done < "$sh_units"
    # shellcheck disable=SC2086 # the directories carry no spaces
    [ -n "$dirs" ] && find $dirs -maxdepth 1 -name 'test_*.sh' 2>/dev/null
} | sed "$SWEEP_NAME_SED" | LC_ALL=C sort -u > "$tmpdir/expected.txt"

ls "$tmpdir" 2>/dev/null | sed -n 's/^PASS_//p;s/^FAIL_//p;s/^SKIP_//p' \
    | LC_ALL=C sort -u > "$tmpdir/reported.txt"

LC_ALL=C comm -23 "$tmpdir/expected.txt" "$tmpdir/reported.txt" > "$out"
wc -l < "$tmpdir/expected.txt" | tr -d ' '
