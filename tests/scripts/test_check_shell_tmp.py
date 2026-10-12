#!/usr/bin/env python3
"""Unit tests for check_shell_tmp.py (#2770)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_shell_tmp as c  # noqa: E402


def flagged(text):
    return [n for n, _ in c.offenders_in(text)]


class FixedTmpPaths(unittest.TestCase):
    def test_a_fixed_path_is_flagged(self):
        self.assertEqual(flagged('cat > /tmp/ae_x.ae << EOF\nmain() {}\nEOF\n'), [1])
        self.assertEqual(flagged('out=$("$AE" build /tmp/ae_bad.ae -o /tmp/ae_out)'), [1])
        self.assertEqual(flagged('gcc -o /tmp/test_map_lua x.c'), [1])

    def test_a_directory_of_its_own_passes(self):
        self.assertEqual(flagged('TMP="$(mktemp -d)"\ncat > "$TMP/x.ae"'), [])
        self.assertEqual(flagged('cat > $AE_TMP/ae_x.ae'), [])

    def test_a_name_built_from_mktemp_or_tmpdir_passes(self):
        self.assertEqual(flagged('TMP="${TMPDIR:-/tmp}/ae_wasmprefix_$$"'), [])
        self.assertEqual(flagged('f=$(mktemp /tmp/ae.XXXXXX)'), [])

    def test_comments_and_heredoc_bodies_are_not_code(self):
        self.assertEqual(flagged('# writes /tmp/ae_x before the fix'), [])
        self.assertEqual(flagged('echo hi  # not /tmp/ae_x'), [])
        self.assertEqual(flagged("cat > \"$T/p.ae\" <<'AE'\npath = \"/tmp/foo\"\nAE\n"), [])
        self.assertEqual(flagged('cat > "$T/p.ae" <<EOF\nx = "/tmp/foo"\nEOF\ncp a /tmp/b'), [4])

    def test_a_waiver_on_the_line_or_above(self):
        self.assertEqual(flagged('cp a /tmp/b  # tmp-ok: the container is ours'), [])
        self.assertEqual(flagged('# tmp-ok: the container is ours\ncp a /tmp/b'), [])

    def test_paths_that_only_end_in_tmp_are_not_flagged(self):
        self.assertEqual(flagged('cp a "$ROOT/build/tmp/x"'), [])
        self.assertEqual(flagged('ls /var/tmp/x'), [])


if __name__ == "__main__":
    unittest.main()
