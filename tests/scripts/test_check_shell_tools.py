#!/usr/bin/env python3
"""Unit tests for check_shell_tools.py (#3110): a cmp or diff command is
flagged unless the file asks `command -v` for it, and text that is no
command (a comment, a string, a heredoc, another word) is not.

Run from anywhere: `python3 tests/scripts/test_check_shell_tools.py`.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_shell_tools as cst  # noqa: E402


def lines(src):
    return [n for n, _ in cst.check_source(src)]


class ToolTest(unittest.TestCase):
    def test_a_bare_comparison_is_flagged(self):
        self.assertEqual(lines('if ! cmp -s "$a" "$b"; then\n'), [1])
        self.assertEqual(lines('cmp "$a" "$b" || fail\n'), [1])
        self.assertEqual(lines('diff -u a b\n'), [1])
        self.assertEqual(lines('x=1; diff a b >/dev/null\n'), [1])

    def test_a_guarded_tool_is_allowed(self):
        src = ('if command -v diff >/dev/null 2>&1; then\n'
               '    diff -u "$1" "$2" | head\n'
               'fi\n')
        self.assertEqual(lines(src), [])

    def test_the_guard_is_per_tool(self):
        src = 'command -v diff >/dev/null && diff a b\ncmp -s a b\n'
        self.assertEqual(lines(src), [2])

    def test_text_that_is_no_command_is_not_flagged(self):
        self.assertEqual(lines('# cmp -s exits non-zero when cmp is missing\n'), [])
        self.assertEqual(lines('echo "diff the two"\n'), [])
        self.assertEqual(lines('git diff --name-only HEAD\n'), [])
        self.assertEqual(lines('same_bytes "$a" "$b" || echo cmp\n'), [])

    def test_a_heredoc_body_is_not_shell(self):
        src = ('python3 - <<\'PY\'\n'
               'diff = a - b\n'
               'PY\n'
               'cmp -s a b\n')
        self.assertEqual(lines(src), [4])


if __name__ == "__main__":
    unittest.main()
