#!/bin/sh
# Build examples/04-interop/04-embedding: greeter.ae as an object file,
# host.c linked against it and the Aether runtime, then run the program.
# Run from the repository root. AE and CC name the tools (default: ae, cc).
set -e
AE="${AE:-ae}"
CC="${CC:-cc}"
here="$(dirname "$0")"
out="build/examples/embedding"
mkdir -p "$out"
"$AE" build --emit=obj "$here/greeter.ae" -o "$out/greeter.o" >/dev/null
# shellcheck disable=SC2046
"$CC" "$here/host.c" "$out/greeter.o" $("$AE" cflags --libs) -o "$out/host"
"$out/host"
