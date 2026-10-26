#!/usr/bin/env python3
"""Unit tests for check_shell_kills.py (#2479): each rule on a small shell
source, flagged and clean, so a rule change here is a red test rather than a
green `make check-tests` that quietly stopped seeing a kill.

Run from anywhere: `python3 tests/scripts/test_check_shell_kills.py`.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_shell_kills as csk  # noqa: E402


def lines(src):
    return [n for n, _ in csk.check_source(src)]


class RememberedPidTest(unittest.TestCase):
    def test_kill_of_a_pid_variable_is_flagged(self):
        self.assertEqual(lines('kill "$SRV_PID" 2>/dev/null || true\n'), [1])
        self.assertEqual(lines('kill $SRV_PID\n'), [1])
        self.assertEqual(lines('kill "${SRV_PID:-}"\n'), [1])

    def test_any_signal_is_flagged(self):
        self.assertEqual(lines('kill -9 "$pid"\n'), [1])
        self.assertEqual(lines('kill -TERM "$pid"\n'), [1])
        self.assertEqual(lines('kill -s KILL "$pid"\n'), [1])
        self.assertEqual(lines('kill -SIGKILL $pid\n'), [1])

    def test_last_background_pid_and_substitutions_are_flagged(self):
        self.assertEqual(lines('kill $!\n'), [1])
        self.assertEqual(lines('kill $(cat "$TMP/pid")\n'), [1])
        self.assertEqual(lines('kill `cat pidfile`\n'), [1])

    def test_a_group_of_a_remembered_pid_is_flagged(self):
        self.assertEqual(lines('kill -- "-$SRV_PID" 2>/dev/null\n'), [1])
        self.assertEqual(lines('kill -9 -$PGID\n'), [1])

    def test_a_literal_pid_is_flagged(self):
        self.assertEqual(lines('kill 1234\n'), [1])
        self.assertEqual(lines('kill -9 -1\n'), [1])

    def test_kills_after_separators_are_seen(self):
        self.assertEqual(lines('[ -n "$P" ] && kill "$P"\n'), [1])
        self.assertEqual(lines('cleanup() { kill "$P"; rm -rf "$T"; }\n'), [1])
        self.assertEqual(lines('for p in $PIDS; do kill "$p"; done\n'), [1])
        self.assertEqual(lines('if true; then kill "$P"; fi\n'), [1])
        self.assertEqual(lines('true || kill "$P"\n'), [1])

    def test_each_kill_on_a_line_counts(self):
        self.assertEqual(len(csk.check_source(
            'kill -- "-$P" 2>/dev/null || kill "$P" 2>/dev/null || true\n')), 2)

    def test_a_job_is_flagged(self):
        # On Windows the job's process is the native program's stand-in.
        self.assertEqual(lines('kill %1\n'), [1])
        self.assertEqual(lines('kill -9 "%$_sj" 2>/dev/null\n'), [1])
        self.assertEqual(lines('kill -s TERM %2\n'), [1])


class TimeoutTest(unittest.TestCase):
    """timeout(1) signals what it bounds at the limit (#3154)."""

    def test_timeout_as_a_command_is_flagged(self):
        self.assertEqual(lines('timeout 60 "$AETHERC" "$T/deep.ae" "$T/out.c"\n'), [1])
        self.assertEqual(lines('gtimeout 30 "$TMP/wscli"\n'), [1])
        self.assertEqual(lines('out=$(timeout -k 5 30 ./prog)\n'), [1])
        self.assertEqual(lines('set +e; timeout 5 ./prog; rc=$?\n'), [1])
        self.assertEqual(lines('command timeout 5 ./prog\n'), [1])

    def test_timeout_held_as_a_prefix_is_flagged(self):
        self.assertEqual(lines('    TIMEOUT="timeout 30"\n'), [1])
        self.assertEqual(lines("TO='gtimeout 60'\n"), [1])
        self.assertEqual(lines('TO=timeout\n'), [1])
        self.assertEqual(lines('TO="timeout -k 5 30"\n'), [1])
        self.assertEqual(lines(
            'if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout 60"\n'), [1])

    def test_asking_for_timeout_is_not_running_it(self):
        self.assertEqual(lines('if command -v timeout >/dev/null 2>&1; then\n'), [])
        self.assertEqual(lines('command -v gtimeout >/dev/null || exit 0\n'), [])

    def test_the_sweep_bound_is_allowed(self):
        self.assertEqual(lines('sweep_timeout_bound TO "$ROOT" 60\n'), [])
        self.assertEqual(lines('$TO "$AETHERC" "$T/deep.ae"\n'), [])
        self.assertEqual(lines('OUT=$(AE_TEST_PORT="$PORT" $TIMEOUT "$TMP/wscli" 2>&1)\n'), [])

    def test_timeout_in_text_is_not_a_command(self):
        self.assertEqual(lines('echo "  [FAIL] no READY within timeout"\n'), [])
        self.assertEqual(lines('# a bare `timeout 60` was GNU coreutils\n'), [])
        self.assertEqual(lines('curl -s --connect-timeout 0.3 --max-time 1 "$U"\n'), [])
        self.assertEqual(lines('AE_SH_TEST_TIMEOUT=420 sh run.sh\n'), [])
        self.assertEqual(lines('MSG="timeout reached"\n'), [])


class AllowedTest(unittest.TestCase):
    def test_signal_zero_is_a_probe(self):
        self.assertEqual(lines('kill -0 "$pid" 2>/dev/null\n'), [])
        self.assertEqual(lines('while kill -0 "$cpid" 2>/dev/null; do\n'), [])
        self.assertEqual(lines('kill -s 0 "$pid"\n'), [])

    def test_the_scripts_own_shell_is_allowed(self):
        self.assertEqual(lines('kill -TERM $$\n'), [])

    def test_listing_signals_is_allowed(self):
        self.assertEqual(lines('kill -l\n'), [])

    def test_helpers_are_not_kill(self):
        self.assertEqual(lines('kill_server "$SRV_PID"\nstop_server "$P"\n'), [])
        self.assertEqual(lines('signal_server TERM "$P"\n'), [])


class NotCodeTest(unittest.TestCase):
    def test_comments_are_not_kills(self):
        self.assertEqual(lines('# kill "$SRV_PID" here\n'), [])
        self.assertEqual(lines('true  # then kill "$P"\n'), [])

    def test_quoted_text_is_not_a_kill(self):
        self.assertEqual(lines('echo "  [SKIP] x: POSIX-only (kill $! semantics)"\n'), [])
        self.assertEqual(lines("echo 'kill \"$P\" by hand'\n"), [])

    def test_a_heredoc_body_is_not_a_kill(self):
        src = ('cat > "$T/x.sh" <<\'EOF\'\nkill "$P"\nEOF\n'
               'kill "$Q"\n')
        self.assertEqual(lines(src), [4])

    def test_a_trap_string_is_code(self):
        self.assertEqual(lines("trap 'kill \"$SRV_PID\"' EXIT\n"), [1])
        self.assertEqual(lines("trap 'rm -rf \"$T\"' EXIT\n"), [])


class ByNameTest(unittest.TestCase):
    def test_pkill_and_killall_are_flagged(self):
        self.assertEqual(lines('pkill -f "$SCRIPT_DIR/server.ae"\n'), [1])
        self.assertEqual(lines('killall server\n'), [1])

    def test_xargs_kill_is_flagged(self):
        self.assertEqual(lines('pgrep -f srv | xargs kill -9\n'), [1])


class WaiverTest(unittest.TestCase):
    def test_waiver_on_the_line(self):
        self.assertEqual(lines('kill -9 "$CHILD"  # kill-ok: a grandchild, POSIX only\n'), [])

    def test_waiver_on_the_comment_line_above(self):
        self.assertEqual(lines('# kill-ok: a grandchild, POSIX only\nkill -9 "$CHILD"\n'), [])

    def test_waiver_does_not_reach_past_one_line(self):
        src = '# kill-ok: a grandchild\nkill -9 "$CHILD"\nkill "$OTHER"\n'
        self.assertEqual(lines(src), [3])


class ScopeTest(unittest.TestCase):
    def test_the_helper_file_is_exempt_and_the_rest_of_tests_is_read(self):
        paths = [os.path.relpath(p, csk.ROOT).replace(os.sep, "/")
                 for p in csk.shell_sources(csk.ROOT)]
        self.assertNotIn("tests/lib/server_jobs.sh", paths)
        self.assertIn("tests/scripts/run_ae_sh_dir.sh", paths)
        self.assertTrue(any(p.startswith("tests/integration/") for p in paths))


if __name__ == "__main__":
    unittest.main()
