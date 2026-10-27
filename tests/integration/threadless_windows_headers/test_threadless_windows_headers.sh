#!/bin/sh
# A Windows build without threads includes <winsock2.h> after a lean
# <windows.h> (#3223): aether_cpu_available.h included the full one, which
# brings the old <winsock.h>, and every socket file after it warned. With
# threads, aether_thread.h includes it lean first, so only this build saw it.
# Windows hosts only: elsewhere there is no <windows.h> to include.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) echo "  [SKIP] threadless_windows_headers: not a Windows host"; exit 0 ;;
esac
CC="${CC:-gcc}"
command -v "$CC" >/dev/null 2>&1 || { echo "  [SKIP] threadless_windows_headers: no $CC"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
# The files that include aether_cpu_available.h, the socket ones among them.
for f in runtime/utils/aether_cpu_detect.c std/net/aether_http_pool.c \
         std/net/aether_http_server.c std/worker/aether_worker.c; do
    if ! "$CC" -fsyntax-only -Werror -Wall -Wno-unused-function -DAETHER_NO_THREADING \
            -I"$ROOT/runtime" -I"$ROOT/runtime/utils" -I"$ROOT/runtime/actors" \
            -I"$ROOT/runtime/scheduler" -I"$ROOT/runtime/memory" -I"$ROOT/runtime/config" \
            -I"$ROOT/std" -I"$ROOT/std/net" -I"$ROOT/std/string" -I"$ROOT/std/worker" \
            "$ROOT/$f" >"$TMP/cc.log" 2>&1; then
        echo "  [FAIL] threadless_windows_headers: $f"
        head -10 "$TMP/cc.log"
        fails=$((fails + 1))
    fi
done
[ "$fails" -eq 0 ] || exit 1
echo "  [PASS] threadless_windows_headers: the files that include aether_cpu_available.h build without threads"
