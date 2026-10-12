#!/usr/bin/env python3
"""Unit tests for check_ae_tmp.py (#2771): each rule on a small Aether
source, flagged and clean, so a rule change here is a red test rather than
a green `make check-tests` that quietly stopped seeing a fixed temp name.

Run from anywhere: `python3 tests/scripts/test_check_ae_tmp.py`.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_ae_tmp as cat  # noqa: E402


def lines(src):
    return [n for n, _ in cat.check_source(src)]


def main_of(body):
    """`body` (lines indented four spaces) inside a main()."""
    return "main() {\n" + "".join("    " + b + "\n" for b in body) + "}\n"


class FixedNameTest(unittest.TestCase):
    def test_a_name_under_a_temp_dir_variable(self):
        src = main_of(['tmp = os.temp_dir()',
                       'path = "${tmp}/aether_fs_copy_test"',
                       'fs.create_dir(path)'])
        self.assertEqual(lines(src), [3])

    def test_a_name_under_temp_dir_inline(self):
        src = main_of(['e = file.write("${os.temp_dir()}/aether_x.txt", "data")'])
        self.assertEqual(lines(src), [2])

    def test_a_tmp_literal(self):
        src = main_of(['tmp = "/tmp/aether_267_regression"', 'fs.write(tmp, "hello")'])
        self.assertEqual(lines(src), [2])

    def test_path_join_under_temp_dir(self):
        src = main_of(['root = path.join(os.temp_dir(), "ae_x")', 'fs.mkdir_p(root)'])
        self.assertEqual(lines(src), [2])

    def test_a_variable_holding_the_temp_dir_as_a_literal(self):
        self.assertEqual(lines(main_of(['t = "/tmp"', 'fs.write("${t}/x", "x")'])), [3])
        self.assertEqual(lines(main_of(['t = "${os.temp_dir()}"', 'fs.write("${t}/x", "x")'])), [3])

    def test_a_const(self):
        src = 'const BIN = "/tmp/child_bin"\nmain() {\n    fs.write(BIN, "x")\n}\n'
        self.assertEqual(lines(src), [1])

    def test_the_line_that_spells_the_name_is_reported(self):
        src = main_of(['tmp = os.temp_dir()',
                       'base = "${tmp}/aether_walk_borrow_test"',
                       'sub = "${base}/nested"',
                       'e = fs.mkdir_p(sub)'])
        self.assertEqual(lines(src), [3])

    def test_one_report_per_name(self):
        src = main_of(['base = "${os.temp_dir()}/b"',
                       'fs.create_dir(base)',
                       'fs.write(base, "x")'])
        self.assertEqual(lines(src), [2])


class WritingCallTest(unittest.TestCase):
    def flagged(self, call):
        src = main_of(['p = "${os.temp_dir()}/aether_probe"', call])
        return lines(src) == [2]

    def test_writes(self):
        for call in ('fs.write(p, "x")', 'fs.write_binary(p, b)', 'fs.write_atomic(p, b)',
                     'io.write_file(p, "x")', 'io.append_file(p, "x")', 'fd, e = io.fd_open_write(p)',
                     'ok = ffi_shim_write_binary(p)', 'ok = wb_probe_write_seed(p)'):
            self.assertTrue(self.flagged(call), call)

    def test_directories(self):
        for call in ('fs.create_dir(p)', 'dir.create(p)', 'create_dir(p)', 'fs.mkdir_p(p)'):
            self.assertTrue(self.flagged(call), call)

    def test_two_path_calls(self):
        for call in ('fs.copy(src, p)', 'fs.move(src, p)', 'fs.rename(src, p)',
                     'fs.symlink("t", p)', 'fs.hard_link(a, p)', 'fs.copy_tree(src, p)'):
            self.assertTrue(self.flagged(call), call)

    def test_open_for_writing(self):
        self.assertTrue(self.flagged('f, e = fs.open(p, "w+")'))
        self.assertTrue(self.flagged('f, e = fs.open(p, "a")'))
        self.assertFalse(self.flagged('f, e = fs.open(p, "r")'))
        self.assertFalse(self.flagged('d, e = avcodec.open(p, 64, 48)'))

    def test_reads_and_queries_are_not_writes(self):
        for call in ('c, e = fs.read(p)', 'd, n, e = fs.read_binary(p)', 'x = fs.exists(p)',
                     'e = fs.delete(p)', 'e = fs.remove_tree(p)', 'k, s, m, e = fs.file_stat(p)',
                     'c = string.copy(p)', 'zip.writer_add(w, p, b, 0, 0)', 'println(p)'):
            self.assertFalse(self.flagged(call), call)

    def test_a_shell_command_naming_it(self):
        src = main_of(['dir = "/tmp/aeth_glob_1367"',
                       '_ = system("rm -rf ${dir}; mkdir -p ${dir}/sub")'])
        self.assertEqual(lines(src), [2])
        self.assertEqual(lines(main_of(['_ = system("mkdir -p /tmp/aeth_x/sub")'])), [2])
        self.assertEqual(lines(main_of(['tmp = os.temp_dir()',
                                        '_ = system("touch ${tmp}/aeth_y")'])), [3])
        self.assertEqual(lines(main_of(['d = "${os.temp_dir()}/aeth_${os.getpid()}"',
                                        '_ = system("mkdir -p ${d}/sub")'])), [])

    def test_only_the_path_written_counts(self):
        # The content written is not a path, and the source of a copy or a
        # link already exists (whatever made it is checked where it did).
        src = main_of(['cfg = "${os.temp_dir()}/ae_cfg_${os.getpid()}"',
                       'e = fs.write(cfg, "/tmp/aether_named_in_the_content")',
                       'b, k, m = fs.copy("/tmp/aether_src", cfg)',
                       'b2, k2, m2 = fs.copy(cfg, "/tmp/aether_dst")'])
        self.assertEqual(lines(src), [5])


class DepthTest(unittest.TestCase):
    def test_a_write_into_a_directory_that_never_exists_makes_nothing(self):
        src = main_of(['tmp = os.temp_dir()',
                       'bad = "${tmp}/aether_no_such_dir_xyz/file.bin"',
                       'e = fs.write_binary(bad, b)'])
        self.assertEqual(lines(src), [])

    def test_mkdir_p_makes_every_directory_on_the_way(self):
        src = main_of(['tmp = os.temp_dir()',
                       'e = fs.mkdir_p("${tmp}/aether_x/src/deep")'])
        self.assertEqual(lines(src), [3])


class PerRunTest(unittest.TestCase):
    def test_getpid_inline(self):
        src = main_of(['tmp = os.temp_dir()',
                       'path = "${tmp}/aether_fs_copy_test_${os.getpid()}"',
                       'fs.create_dir(path)'])
        self.assertEqual(lines(src), [])

    def test_a_pid_variable(self):
        src = main_of(['tmp = os.temp_dir()', 'pid = os.getpid()',
                       'e = fs.write("${tmp}/aether_x_${pid}.txt", "x")'])
        self.assertEqual(lines(src), [])

    def test_a_name_variable_built_on_getpid(self):
        src = main_of(['name = "aether_fs_realpath_test_${os.getpid()}"',
                       'tmpdir = "${os.temp_dir()}/${name}"',
                       'fs.create_dir(tmpdir)'])
        self.assertEqual(lines(src), [])

    def test_a_path_under_a_per_run_directory(self):
        src = main_of(['base = "${os.temp_dir()}/ae_x_${os.getpid()}"',
                       'fs.write("${base}/a.txt", "a")'])
        self.assertEqual(lines(src), [])

    def test_make_temp_file(self):
        src = main_of(['tmp, terr = fs.make_temp_file(os.temp_dir(), "ae-sha-")',
                       'werr = fs.write(tmp, "hello")'])
        self.assertEqual(lines(src), [])

    def test_a_value_this_file_does_not_assign(self):
        src = ('write_into(dir: string, name: string) {\n'
               '    tmp = os.temp_dir()\n'
               '    e = fs.write("${tmp}/${name}", "x")\n'
               '}\n')
        self.assertEqual(lines(src), [])

    def test_a_counter_is_not_per_run(self):
        src = main_of(['tmp = os.temp_dir()', 'i = 0',
                       'e = fs.write("${tmp}/f_${i}", "x")'])
        self.assertEqual(lines(src), [4])


class NotWrittenTest(unittest.TestCase):
    def test_a_path_used_as_a_string(self):
        src = main_of(['root = "/tmp/x"', 'ml = "${root}/a"',
                       'check("outer", ml, "/tmp/x/a")', 'use(ml)'])
        self.assertEqual(lines(src), [])

    def test_a_missing_path_that_is_only_read(self):
        src = main_of(['missing = "/tmp/aether-definitely-not-here-9471"',
                       'c1, e1 = fs.read(missing)',
                       '_h2, e2 = cryptography.sha256_file("/tmp/ae-not-a-file")'])
        self.assertEqual(lines(src), [])

    def test_comments_are_not_code(self):
        src = main_of(['// fs.write("/tmp/x.txt", "x")', '/* fs.create_dir("/tmp/y") */'])
        self.assertEqual(lines(src), [])

    def test_a_heredoc_body_is_not_code(self):
        src = main_of(['s = <<EOF', 'fs.write("/tmp/x.txt", "x")', 'EOF',
                       'fs.write("/tmp/y.txt", "y")'])
        self.assertEqual(lines(src), [5])

    def test_a_function_starts_a_fresh_scope(self):
        src = ('main() {\n'
               '    path = "/tmp/aether_x"\n'
               '    println(path)\n'
               '}\n'
               'save(path: string) {\n'
               '    e = fs.write(path, "x")\n'
               '}\n'
               'fn save2(path: string) -> int {\n'
               '    e = fs.write(path, "x")\n'
               '    return 0\n'
               '}\n')
        self.assertEqual(lines(src), [])

    def test_a_top_level_const_reaches_every_function(self):
        src = ('const BIN = "/tmp/child_bin"\n'
               'build() {\n'
               '    println(BIN)\n'
               '}\n'
               'main() {\n'
               '    fs.write(BIN, "x")\n'
               '}\n')
        self.assertEqual(lines(src), [1])


class WaiverTest(unittest.TestCase):
    def test_waiver_on_the_line(self):
        src = main_of(['e = fs.rename("${os.temp_dir()}/no_src", "${os.temp_dir()}/dst")'
                       '  // tmp-ok: the source never exists'])
        self.assertEqual(lines(src), [])

    def test_waiver_on_the_comment_line_above(self):
        src = main_of(['// tmp-ok: the source never exists',
                       'e = fs.rename("${os.temp_dir()}/no_src", "${os.temp_dir()}/dst")'])
        self.assertEqual(lines(src), [])

    def test_waiver_does_not_reach_past_one_line(self):
        src = main_of(['// tmp-ok: the source never exists',
                       'e = fs.rename("${os.temp_dir()}/no_src", "${os.temp_dir()}/dst")',
                       'fs.write("${os.temp_dir()}/other", "x")'])
        self.assertEqual(lines(src), [4])


class ScopeTest(unittest.TestCase):
    def test_test_programs_are_read_and_library_code_is_not(self):
        paths = [os.path.relpath(p, cat.ROOT).replace(os.sep, "/")
                 for p in cat.test_programs(cat.ROOT)]
        self.assertIn("tests/regression/test_fs_copy.ae", paths)
        self.assertIn("tests/integration/fs_write_binary_nul/probe.ae", paths)
        self.assertIn("std/cas/test_cas_store.ae", paths)
        self.assertNotIn("std/os/module.ae", paths)
        self.assertNotIn("std/mutation/module.ae", paths)


if __name__ == "__main__":
    unittest.main()
