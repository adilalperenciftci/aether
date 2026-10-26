[ "$got" -eq 3 ] || fail "stderr has $got lines, want 3"grep -qF 'disk 100%s full %d' "$TMPDIR/err.log" || fail "a % in the message was not written as text" "$TMPDIR/err.log"
#!/bin/sh
# Regression (#3149): std.log takes "" and "-" for stderr, prints nothing of
# its own, and a re-init after a stderr target leaves stderr open. See
# probe.ae.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AE="$ROOT/build/ae"
[ -x "$AE" ] || AE="$ROOT/build/ae.exe"

TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
fail() { echo "  [FAIL] log_to_stderr: $1"; shift; for f in "$@"; do sed 's/^/    | /' "$f" | head -8; done; exit 1; }

"$AE" build "$SCRIPT_DIR/probe.ae" -o "$TMPDIR/probe" >"$TMPDIR/build.log" 2>&1 \
    || fail "build failed" "$TMPDIR/build.log"

(cd "$TMPDIR" && ./probe >out.log 2>err.log)
rc=$?
[ $rc -eq 0 ] || fail "probe exited $rc" "$TMPDIR/out.log" "$TMPDIR/err.log"
[ "$(tr -d '\r' < "$TMPDIR/out.log")" = "ok" ] || fail "stdout is not just ok" "$TMPDIR/out.log"

# Exactly three stderr lines: no "[LOG] Failed to open", no message below
# the level, the % message as written, and the last line proves stderr
# survived the re-init.
got="$(tr -d '\r' < "$TMPDIR/err.log" | grep -c .)"
grep -q 'WARN.*first to stderr' "$TMPDIR/err.log" || fail "the first stderr line is missing" "$TMPDIR/err.log"
grep -qF 'disk 100%s full %d' "$TMPDIR/err.log" || fail "a % in the message was not written as text" "$TMPDIR/err.log"
grep -q 'ERROR.*second to stderr' "$TMPDIR/err.log" || fail "stderr was closed by the re-init" "$TMPDIR/err.log"
[ "$got" -eq 3 ] || fail "stderr has $got lines, want 3" "$TMPDIR/err.log"
grep -q 'into the file' "$TMPDIR/app.log" || fail "the file target got nothing" "$TMPDIR/app.log"
[ ! -e "$TMPDIR/-" ] || fail "init(\"-\") created a file named -"

echo "  [PASS] log_to_stderr"
