#!/bin/sh
# Part of examples/06-tooling/05-ae-help/broken.ae: `ae help` on the
# script, then again once the two rewrites it offers are made, as
# `ae help --fix` makes them at a terminal. The second run is in a copy, so
# broken.ae stays broken.
set -e
here=examples/06-tooling/05-ae-help
ae help "$here/broken.ae" --lib "$here/lib"

copy="$(mktemp -d)"
trap 'rm -rf "$copy"' EXIT
cp -r "$here/lib" "$copy/lib"
sed -e 's/port: 9990/port(9990)/' -e 's/host = "127.0.0.1"/host("127.0.0.1")/' \
    "$here/broken.ae" > "$copy/broken.ae"
echo "--- with those two rewrites made:"
cd "$copy"
ae help broken.ae --lib lib
