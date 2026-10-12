#!/usr/bin/env python3
"""Unit tests for check_test_verdicts.py's dropped-verdict rule (#2678):
a std.spec suite that calls run_summary as a bare statement exits 0 with
failing cases, since run_summary returns the verdict and does not exit.

Run from anywhere: `python3 tests/scripts/test_check_test_verdicts.py`.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_test_verdicts as ctv  # noqa: E402


def drops(src):
    return bool(ctv.DROPPED_SUMMARY.search(ctv.strip_comments(src)))


class DroppedSummaryTest(unittest.TestCase):
    def test_a_bare_call_drops_the_verdict(self):
        self.assertTrue(drops("main() {\n    fw = spec.init()\n    spec.run_summary(fw)\n}\n"))

    def test_a_bare_call_through_a_selective_import_drops_it(self):
        self.assertTrue(drops("main() {\n    run_summary(fw)\n}\n"))

    def test_returning_the_verdict_keeps_it(self):
        self.assertFalse(drops("main() {\n    return spec.run_summary(fw)\n}\n"))

    def test_binding_or_exiting_with_the_verdict_keeps_it(self):
        self.assertFalse(drops("main() {\n    v = spec.run_summary(fw)\n    return v\n}\n"))
        self.assertFalse(drops("main() {\n    exit(spec.run_summary(fw))\n}\n"))

    def test_a_commented_call_is_not_code(self):
        self.assertFalse(drops("main() {\n    // spec.run_summary(fw)\n    return 0\n}\n"))


if __name__ == "__main__":
    unittest.main()
