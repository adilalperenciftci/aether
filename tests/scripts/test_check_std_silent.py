#!/usr/bin/env python3
"""Unit tests for check_std_silent.py (#3131): each rule on a small C source,
flagged and clean, so a rule change here is a red test rather than a green
`make check-docs` that quietly stopped seeing a print.

Run from anywhere: `python3 tests/scripts/test_check_std_silent.py`.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_std_silent as css  # noqa: E402


def lines(src):
    return [n for n, _ in css.check_source(src)]


class FlaggedTest(unittest.TestCase):
    def test_printf(self):
        self.assertEqual(lines('void f(void) {\n    printf("up\\n");\n}\n'), [2])

    def test_fprintf_to_stderr(self):
        self.assertEqual(lines('int f(void) {\n    fprintf(stderr, "bad\\n");\n    return -1;\n}\n'), [2])

    def test_stream_on_a_later_line_of_the_call(self):
        src = 'void f(int n) {\n    fprintf(\n        stdout,\n        "%d", n);\n}\n'
        self.assertEqual(lines(src), [2])

    def test_puts_putchar_perror(self):
        src = 'void f(void) {\n    puts("a");\n    putchar(10);\n    perror("open");\n}\n'
        self.assertEqual(lines(src), [2, 3, 4])

    def test_fputs_and_fwrite_to_a_stream(self):
        src = 'void f(const char* s) {\n    fputs(s, stderr);\n    fwrite(s, 1, 3, stdout);\n}\n'
        self.assertEqual(lines(src), [2, 3])


class CleanTest(unittest.TestCase):
    def test_a_write_to_a_file(self):
        self.assertEqual(lines('void f(FILE* fp) {\n    fprintf(fp, "x");\n    fputs("y", fp);\n}\n'), [])

    def test_snprintf_and_longer_names(self):
        src = 'void f(char* b) {\n    snprintf(b, 4, "x");\n    ma_printf("x");\n    o->printf("x");\n}\n'
        self.assertEqual(lines(src), [])

    def test_comments_and_strings(self):
        src = ('/* printf("no"); fprintf(stderr, "no"); */\n'
               '// puts("no");\n'
               'const char* s = "printf(\\"no\\")";\n')
        self.assertEqual(lines(src), [])

    def test_fflush_is_not_a_write(self):
        self.assertEqual(lines('void f(void) {\n    fflush(stdout);\n}\n'), [])

    def test_stream_named_in_the_next_statement_does_not_count(self):
        src = 'void f(FILE* fp) {\n    fprintf(fp, "x");\n    fflush(stderr);\n}\n'
        self.assertEqual(lines(src), [])


class WaiverTest(unittest.TestCase):
    def test_on_the_line(self):
        src = 'void f(void) {\n    fprintf(stderr, "oom\\n");  /* silent-ok: last line before abort */\n    abort();\n}\n'
        self.assertEqual(lines(src), [])

    def test_on_the_comment_line_above(self):
        src = 'void f(void) {\n    /* silent-ok: last line before abort */\n    fprintf(stderr, "oom\\n");\n}\n'
        self.assertEqual(lines(src), [])

    def test_two_lines_above_does_not_count(self):
        src = 'void f(void) {\n    /* silent-ok: no */\n    int x = 0;\n    fprintf(stderr, "%d", x);\n}\n'
        self.assertEqual(lines(src), [4])


class TreeTest(unittest.TestCase):
    def test_product_and_vendored_sources_are_skipped(self):
        rels = [rel for rel, _ in css.sources(css.ROOT)]
        self.assertFalse([r for r in rels if r.startswith(css.PRODUCT + css.VENDORED)])
        self.assertIn("std/net/aether_http_server.c", rels)


if __name__ == "__main__":
    unittest.main()
